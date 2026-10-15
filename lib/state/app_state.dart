import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../data/sample_data.dart';
import '../models/models.dart';

/// All app state for the prototype. Swap the sample data and the simulated replies for a real
/// backend later; screens only talk to this class.
class AppState extends ChangeNotifier {
  AppState({
    List<Profile>? profiles,
    this.replyDelay = const Duration(milliseconds: 1400),
    this.acceptDelay = const Duration(seconds: 4),
  }) : _profiles = profiles ?? buildSampleProfiles() {
    _seedConversations();
    _seedRequests();
  }

  final Duration replyDelay;

  /// How long the simulated other person takes to answer a chat request.
  final Duration acceptDelay;
  final List<Profile> _profiles;
  final Set<String> _favorites = {};
  final Set<String> _blocked = {};
  final Map<String, Conversation> _conversations = {};
  final _rnd = Random(3);
  int _msgSeq = 0;

  // ---- me ----
  bool onboarded = false;
  String myName = '';
  int myAge = 25;
  String myBio = '';
  Set<LookingFor> myLookingFor = {LookingFor.chat, LookingFor.friends};
  bool showDistance = true;
  bool showOnline = true;

  /// My private album. Sent automatically to anyone whose chat request I accept.
  final List<AlbumPhoto> myAlbum = [
    const AlbumPhoto(id: 'me-0', hue: 28, subject: PhotoSubject.selfie),
    const AlbumPhoto(id: 'me-1', hue: 200, subject: PhotoSubject.beach),
    const AlbumPhoto(id: 'me-2', hue: 330, subject: PhotoSubject.nightOut),
  ];
  int _photoSeq = 3;

  void addMyPhoto(PhotoSubject subject) {
    myAlbum.add(AlbumPhoto(
        id: 'me-${_photoSeq++}',
        hue: _rnd.nextDouble() * 360,
        subject: subject));
    notifyListeners();
  }

  void removeMyPhoto(String id) {
    myAlbum.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  /// One-line notices for the UI to show as snackbars (e.g. "Jordan accepted your request").
  final _events = StreamController<String>.broadcast();
  Stream<String> get events => _events.stream;

  @override
  void dispose() {
    _events.close();
    super.dispose();
  }

  void completeOnboarding(
      {required String name,
      required int age,
      required Set<LookingFor> lookingFor}) {
    myName = name.trim();
    myAge = age;
    myLookingFor = lookingFor;
    onboarded = true;
    notifyListeners();
  }

  void updateMe({String? name, String? bio, bool? distance, bool? online}) {
    if (name != null) myName = name.trim();
    if (bio != null) myBio = bio.trim();
    if (distance != null) showDistance = distance;
    if (online != null) showOnline = online;
    notifyListeners();
  }

  // ---- explore ----
  ExploreFilters _filters = const ExploreFilters();
  ExploreFilters get filters => _filters;
  set filters(ExploreFilters f) {
    _filters = f;
    notifyListeners();
  }

  List<Profile> get visibleProfiles => _profiles
      .where((p) => !_blocked.contains(p.id) && _filters.matches(p))
      .toList();

  List<Profile> get favoriteProfiles => _profiles
      .where((p) => _favorites.contains(p.id) && !_blocked.contains(p.id))
      .toList();

  int get onlineCount =>
      _profiles.where((p) => p.online && !_blocked.contains(p.id)).length;

  Profile? profileById(String id) {
    for (final p in _profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  bool isFavorite(String id) => _favorites.contains(id);

  void toggleFavorite(String id) {
    _favorites.contains(id) ? _favorites.remove(id) : _favorites.add(id);
    notifyListeners();
  }

  void block(String id) {
    _blocked.add(id);
    _favorites.remove(id);
    _conversations.remove(id);
    _connections.remove(id);
    _requests.remove(id);
    notifyListeners();
  }

  // ---- chat requests ----
  // Nobody can message anyone until a request is accepted. Accepting automatically shares the
  // accepter's album with the person who asked, and opens the chat for both.
  final Map<String, Connection> _connections = {};
  final Map<String, ChatRequest> _requests = {};

  Connection connectionWith(String id) => _connections[id] ?? Connection.none;
  bool canChat(String id) => connectionWith(id) == Connection.connected;
  ChatRequest? requestWith(String id) => _requests[id];

  List<ChatRequest> get incomingRequests => _requestsWhere(Connection.incoming);
  List<ChatRequest> get outgoingRequests => _requestsWhere(Connection.outgoing);

  List<ChatRequest> _requestsWhere(Connection c) {
    final list = _requests.values
        .where((r) =>
            _connections[r.profileId] == c && !_blocked.contains(r.profileId))
        .toList();
    list.sort((a, b) => b.sentAt.compareTo(a.sentAt));
    return list;
  }

  void sendRequest(Profile p, {String? note}) {
    if (connectionWith(p.id) != Connection.none) return;
    final n = note?.trim();
    _connections[p.id] = Connection.outgoing;
    _requests[p.id] = ChatRequest(
        profileId: p.id,
        sentAt: DateTime.now(),
        note: n == null || n.isEmpty ? null : n);
    notifyListeners();
    // Simulated: the other person accepts after a moment.
    Timer(acceptDelay, () {
      if (connectionWith(p.id) != Connection.outgoing) return;
      _connect(p, iAccepted: false);
      _events.add('${p.name} accepted your request and shared their album 📸');
    });
  }

  void cancelRequest(String id) {
    if (connectionWith(id) != Connection.outgoing) return;
    _connections.remove(id);
    _requests.remove(id);
    notifyListeners();
  }

  void acceptRequest(Profile p) {
    if (connectionWith(p.id) != Connection.incoming) return;
    _connect(p, iAccepted: true);
  }

  void declineRequest(String id) {
    if (connectionWith(id) != Connection.incoming) return;
    _connections.remove(id);
    _requests.remove(id);
    notifyListeners();
  }

  void _connect(Profile p, {required bool iAccepted}) {
    final req = _requests.remove(p.id);
    _connections[p.id] = Connection.connected;
    final c = conversationWith(p);
    final now = DateTime.now();
    if (req?.note != null) {
      // the request note becomes the first message, from whoever asked
      c.messages.add(Message(
          id: 'm${_msgSeq++}',
          fromMe: iAccepted ? false : true,
          text: req!.note!,
          sentAt: req.sentAt));
    }
    c.messages.add(Message(
      id: 'm${_msgSeq++}',
      fromMe: iAccepted,
      kind: MessageKind.notice,
      text: iAccepted
          ? 'You accepted ${p.name}\'s request'
          : '${p.name} accepted your request',
      sentAt: now,
    ));
    c.messages.add(Message(
      id: 'm${_msgSeq++}',
      fromMe: iAccepted,
      kind: MessageKind.album,
      text:
          iAccepted ? 'You shared your album' : '${p.name} shared their album',
      album: iAccepted ? List.of(myAlbum) : p.album,
      sentAt: now,
    ));
    if (!iAccepted && _openChat != p.id) c.unread++;
    notifyListeners();
  }

  Future<void> refresh() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _profiles.shuffle(_rnd);
    _profiles.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    notifyListeners();
  }

  // ---- chat ----
  List<Conversation> get conversations {
    final list =
        _conversations.values.where((c) => c.messages.isNotEmpty).toList();
    list.sort((a, b) => b.last!.sentAt.compareTo(a.last!.sentAt));
    return list;
  }

  int get totalUnread =>
      _conversations.values.fold(0, (sum, c) => sum + c.unread);

  /// Unread messages plus requests waiting for my answer, for the Chats tab badge.
  int get chatsBadge => totalUnread + incomingRequests.length;

  Conversation conversationWith(Profile p) =>
      _conversations.putIfAbsent(p.id, () => Conversation(profile: p));

  void markRead(Profile p) {
    final c = _conversations[p.id];
    if (c == null || c.unread == 0) return;
    c.unread = 0;
    notifyListeners();
  }

  void deleteConversation(String id) {
    _conversations.remove(id);
    notifyListeners();
  }

  /// Sends a message and simulates the other person reading and answering.
  void send(Profile p, String text, {bool activeChat = true}) {
    final t = text.trim();
    if (t.isEmpty || !canChat(p.id)) return;
    final c = conversationWith(p);
    final msg = Message(
        id: 'm${_msgSeq++}',
        fromMe: true,
        text: t,
        sentAt: DateTime.now(),
        status: MessageStatus.sent);
    c.messages.add(msg);
    notifyListeners();

    Timer(replyDelay ~/ 2, () {
      msg.status = MessageStatus.read;
      c.typing = true;
      notifyListeners();
    });
    Timer(replyDelay, () {
      if (!_conversations.containsKey(p.id)) return;
      c.typing = false;
      c.messages.add(Message(
        id: 'm${_msgSeq++}',
        fromMe: false,
        text: sampleReplies[_rnd.nextInt(sampleReplies.length)],
        sentAt: DateTime.now(),
      ));
      if (!activeChat || _openChat != p.id) c.unread++;
      notifyListeners();
    });
  }

  String? _openChat;
  void setOpenChat(String? id) => _openChat = id;

  void _seedConversations() {
    final now = DateTime.now();
    final seeds = _profiles.take(5).toList();
    const openers = [
      ['Hey there! Saw you like hiking too', 'We should do a trail sometime'],
      ['Hi! Love your bio 😄'],
      ['Morning! ☕'],
      ['Are you going to the event Saturday?'],
      ['Haha that photo is great'],
    ];
    for (var i = 0; i < seeds.length; i++) {
      _connections[seeds[i].id] = Connection.connected;
      final c = conversationWith(seeds[i]);
      c.messages.add(Message(
        id: 'm${_msgSeq++}',
        fromMe: false,
        kind: MessageKind.album,
        text: '${seeds[i].name} shared their album',
        album: seeds[i].album,
        sentAt: now.subtract(Duration(minutes: 9 + i * 41)),
      ));
      final lines = openers[i];
      for (var j = 0; j < lines.length; j++) {
        c.messages.add(Message(
          id: 'm${_msgSeq++}',
          fromMe: false,
          text: lines[j],
          sentAt: now.subtract(Duration(minutes: 7 + i * 41 - j)),
        ));
      }
      c.unread = i < 2 ? lines.length : 0;
    }
  }

  void _seedRequests() {
    final now = DateTime.now();
    const notes = [
      'Hey! Saw we\'re both into coffee ☕',
      null,
      'Hi! You seem cool, chat?'
    ];
    final from = _profiles.skip(5).take(3).toList();
    for (var i = 0; i < from.length; i++) {
      _connections[from[i].id] = Connection.incoming;
      _requests[from[i].id] = ChatRequest(
          profileId: from[i].id,
          sentAt: now.subtract(Duration(minutes: 3 + i * 25)),
          note: notes[i]);
    }
  }
}

/// Makes [AppState] available to the widget tree and rebuilds dependents when it changes.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
