import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../data/sample_data.dart';
import '../models/models.dart';

/// All app state for the prototype. Swap the sample data and the simulated replies for a real
/// backend later; screens only talk to this class.
class AppState extends ChangeNotifier {
  AppState({List<Profile>? profiles, this.replyDelay = const Duration(milliseconds: 1400)})
      : _profiles = profiles ?? buildSampleProfiles() {
    _seedConversations();
  }

  final Duration replyDelay;
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

  void completeOnboarding({required String name, required int age, required Set<LookingFor> lookingFor}) {
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

  List<Profile> get visibleProfiles =>
      _profiles.where((p) => !_blocked.contains(p.id) && _filters.matches(p)).toList();

  List<Profile> get favoriteProfiles =>
      _profiles.where((p) => _favorites.contains(p.id) && !_blocked.contains(p.id)).toList();

  int get onlineCount => _profiles.where((p) => p.online && !_blocked.contains(p.id)).length;

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
    final list = _conversations.values.where((c) => c.messages.isNotEmpty).toList();
    list.sort((a, b) => b.last!.sentAt.compareTo(a.last!.sentAt));
    return list;
  }

  int get totalUnread => _conversations.values.fold(0, (sum, c) => sum + c.unread);

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
    if (t.isEmpty) return;
    final c = conversationWith(p);
    final msg = Message(id: 'm${_msgSeq++}', fromMe: true, text: t, sentAt: DateTime.now(), status: MessageStatus.sent);
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

  /// A quick, low-pressure hello from Explore or a profile.
  void wave(Profile p) => send(p, '👋', activeChat: false);

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
      final c = conversationWith(seeds[i]);
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
}

/// Makes [AppState] available to the widget tree and rebuilds dependents when it changes.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
