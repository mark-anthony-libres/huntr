import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../data/sample_data.dart';
import '../models/models.dart';
import '../services/device_preferences.dart';
import '../services/huntr_backend.dart' show AnonymousName;
import '../theme.dart';

/// All app state for the prototype. Swap the sample data and the simulated replies for a real
/// backend later; screens only talk to this class.
class AppState extends ChangeNotifier {
  AppState({
    List<Profile>? profiles,
    this.replyDelay = const Duration(milliseconds: 1400),
    this.acceptDelay = const Duration(seconds: 4),
    this.onSessionEnd,
    this.devicePreferences,
    bool sampleAlbums = true,
  }) : _profiles = profiles ?? buildSampleProfiles() {
    if (sampleAlbums) myAlbums.addAll(_sampleAlbums());
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

  // ---- session ----
  /// Backend session token. Nothing past the sign-in screen is shown without it.
  String? sessionToken;

  bool get signedIn => sessionToken != null;

  /// A new user must accept the agreement before onboarding. Kept for this
  /// session only; acceptance isn't recorded on the backend yet.
  bool agreementAccepted = false;

  void startSession(String token) {
    sessionToken = token;
    notifyListeners();
  }

  void acceptAgreement() {
    agreementAccepted = true;
    notifyListeners();
  }

  /// Runs whenever the session ends (e.g. clears my photos on the device).
  final Future<void> Function()? onSessionEnd;

  /// Back to sign-in, e.g. when the backend rejects the token.
  void endSession() {
    unawaited(onSessionEnd?.call());
    sessionToken = null;
    profilePhotos = const [];
    maxProfilePhotos = null;
    if (albumLimits != null) myAlbums.clear(); // they came from the backend
    nearby = null;
    nearbyNextOffset = null;
    myUserId = null;
    myStats = const ProfileStats();
    anonymousMessaging = true;
    notifications = (taps: true, messages: true, storyReplies: true);
    _anonymousName = null;
    myIsNew = false;
    albumLimits = null;
    onboarded = false;
    agreementAccepted = false;
    notifyListeners();
  }

  // ---- me ----
  bool onboarded = false;

  /// Where I am: set at onboarding, then refreshed each time the app opens.
  GeoPoint? myLocation;

  void updateMyLocation(GeoPoint location) {
    myLocation = location;
    notifyListeners();
  }

  String myName = '';
  int myAge = 25;
  String myBio = '';
  Set<LookingFor> myLookingFor = {LookingFor.chat, LookingFor.friends};
  bool showDistance = true;
  bool showOnline = true;

  /// On Explore's map (blurred), while showing my distance too.
  bool showOnMap = true;

  /// I may send anonymous messages (Settings); the backend enforces it.
  bool anonymousMessaging = true;

  /// My anonymous name in anonymous chats and Threads (null: not loaded).
  AnonymousName? _anonymousName;
  AnonymousName? get anonymousName => _anonymousName;
  set anonymousName(AnonymousName? name) {
    _anonymousName = name;
    notifyListeners();
  }

  /// Push notifications for each kind (Settings > Notifications), as saved
  /// on the backend.
  ({bool taps, bool messages, bool storyReplies}) notifications =
      (taps: true, messages: true, storyReplies: true);

  void updateNotifications({bool? taps, bool? messages, bool? storyReplies}) {
    notifications = (
      taps: taps ?? notifications.taps,
      messages: messages ?? notifications.messages,
      storyReplies: storyReplies ?? notifications.storyReplies,
    );
    notifyListeners();
  }

  void setAnonymousMessaging(bool enabled) {
    anonymousMessaging = enabled;
    notifyListeners();
  }

  /// My stats: height, weight, body type, position, ..., Show Age, and
  /// the units I see heights and weights in.
  ProfileStats myStats = const ProfileStats();

  void setMyStats(ProfileStats stats) {
    myStats = stats;
    notifyListeners();
  }

  /// The sexual position my profile shows (null: do not show).
  SexualPosition? get mySexualPosition => myStats.sexualPosition;

  /// My profile as other people see it (for "View profile").
  /// My user id and whether my account is new, from the backend (for my
  /// profile as others see it).
  int? myUserId;
  bool myIsNew = false;

  /// Built by the same rules as other people's profiles, so the preview
  /// matches what they see: no alias means no name, the same avatar colour,
  /// and the "New" badge.
  Profile get myPublicProfile => Profile(
        id: 'me',
        // a real user: my photos show (as others see them)
        backendId: myUserId,
        name: myName.trim(),
        isNew: myIsNew,
        age: myAge,
        distanceKm: 0,
        bio: myBio,
        interests: const [],
        lookingFor: myLookingFor,
        // as others see it: no age when I hide it
        ageHidden: !myStats.showAge,
        stats: myStats,
        // others only see the green dot when it's turned on
        online: showOnline,
        lastActive: DateTime.now(),
        hue: myUserId == null ? 28 : avatarHueFor(myUserId!),
        photoUrls: [for (final photo in profilePhotos) photo.url],
      );

  // ---- my profile photos (from the backend) ----
  /// My profile photos, default first. Loaded from the backend; never edited
  /// here directly.
  List<ProfilePhoto> profilePhotos = const [];

  /// The most profile photos allowed, as set by the backend (null until loaded).
  int? maxProfilePhotos;

  ProfilePhoto? get defaultPhoto {
    for (final photo in profilePhotos) {
      if (photo.isDefault) return photo;
    }
    return null;
  }

  void setProfilePhotos(List<ProfilePhoto> photos, {required int maxPhotos}) {
    profilePhotos = List.unmodifiable(photos);
    maxProfilePhotos = maxPhotos;
    notifyListeners();
  }

  // ---- my albums ----
  /// My private albums. One of them is sent when I send or accept a chat request.
  /// From the backend (see [setMyAlbums]); sample albums when there is none.
  final List<Album> myAlbums = [];

  /// What my albums may hold, as set by the backend (null until loaded, and
  /// for sample albums).
  AlbumLimits? albumLimits;

  /// My albums as loaded from the backend.
  void setMyAlbums(List<Album> albums, AlbumLimits limits) {
    myAlbums
      ..clear()
      ..addAll(albums);
    albumLimits = limits;
    notifyListeners();
  }

  /// One of my albums as the backend returned it after a change.
  void replaceMyAlbum(Album album) {
    final index = myAlbums.indexWhere((a) => a.id == album.id);
    if (index < 0) {
      myAlbums.add(album);
    } else {
      myAlbums[index] = album;
    }
    notifyListeners();
  }

  static List<Album> _sampleAlbums() => [
        Album(
            id: 'me-al0',
            name: 'Private',
            photos: const [
              AlbumPhoto(
                  id: 'me-al0-0', hue: 330, subject: PhotoSubject.selfie),
              AlbumPhoto(
                  id: 'me-al0-1', hue: 300, subject: PhotoSubject.nightOut),
              AlbumPhoto(id: 'me-al0-2', hue: 20, subject: PhotoSubject.gym),
            ].toList()),
        Album(
            id: 'me-al1',
            name: 'Weekend',
            photos: const [
              AlbumPhoto(id: 'me-al1-0', hue: 200, subject: PhotoSubject.beach),
              AlbumPhoto(id: 'me-al1-1', hue: 120, subject: PhotoSubject.hike),
            ].toList()),
      ];
  int _photoSeq = 0;
  int _albumSeq = 0;

  AlbumPhoto _newPhoto(PhotoSubject s) => AlbumPhoto(
      id: 'me-new${_photoSeq++}', hue: _rnd.nextDouble() * 360, subject: s);

  Album? myAlbumById(String? id) {
    for (final a in myAlbums) {
      if (a.id == id) return a;
    }
    return null;
  }

  Album createAlbum(String name) {
    final a = Album(
        id: 'me-album-${_albumSeq++}',
        name: name.trim().isEmpty ? 'New album' : name.trim());
    myAlbums.add(a);
    notifyListeners();
    return a;
  }

  void renameAlbum(String id, String name) {
    final a = myAlbumById(id);
    if (a == null || name.trim().isEmpty) return;
    a.name = name.trim();
    notifyListeners();
  }

  void deleteAlbum(String id) {
    myAlbums.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  void addPhotoToAlbum(String albumId, PhotoSubject s) {
    myAlbumById(albumId)?.photos.add(_newPhoto(s));
    notifyListeners();
  }

  /// Without a backend: moves an album's photo from [from] to [to].
  void movePhotoInAlbum(String albumId, int from, int to) {
    final photos = myAlbumById(albumId)?.photos;
    if (photos == null) return;
    photos.insert(to, photos.removeAt(from));
    notifyListeners();
  }

  void removePhotoFromAlbum(String albumId, String photoId) {
    myAlbumById(albumId)?.photos.removeWhere((p) => p.id == photoId);
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
      required Set<LookingFor> lookingFor,
      String bio = '',
      GeoPoint? location}) {
    myName = name.trim();
    myAge = age;
    myLookingFor = lookingFor;
    myBio = bio.trim();
    myLocation = location;
    onboarded = true;
    notifyListeners();
  }

  void updateMe(
      {String? name,
      String? bio,
      int? age,
      Set<LookingFor>? lookingFor,
      bool? distance,
      bool? online,
      bool? onMap}) {
    if (name != null) myName = name.trim();
    if (bio != null) myBio = bio.trim();
    if (age != null) myAge = age;
    if (lookingFor != null) myLookingFor = lookingFor;
    if (distance != null) showDistance = distance;
    if (online != null) showOnline = online;
    if (onMap != null) showOnMap = onMap;
    notifyListeners();
  }

  // ---- explore ----
  ExploreFilters _filters = const ExploreFilters();
  ExploreFilters get filters => _filters;
  set filters(ExploreFilters f) {
    _filters = f;
    notifyListeners();
  }

  /// Choices kept on this device between launches (none in tests).
  final DevicePreferences? devicePreferences;

  /// "Find your vibe" on Explore. Hidden by swiping it away, tapping Hide, or
  /// the switch in Settings; remembered on this device ([devicePreferences]).
  bool _showVibeBanner = true;
  bool get showVibeBanner => _showVibeBanner;
  set showVibeBanner(bool show) {
    if (_showVibeBanner == show) return;
    _showVibeBanner = show;
    notifyListeners();
    unawaited(devicePreferences?.saveShowVibeBanner(show).catchError(
        (Object error) => debugPrint('Vibe banner choice not saved: $error')));
  }

  /// The theme the app wears ([HuntrColors.palette]); the app's root
  /// listens to redraw everything when it changes. Remembered on this device.
  final appearance = ValueNotifier<HuntrPalette>(HuntrColors.palette);

  void usePalette(HuntrPalette palette) {
    if (appearance.value.id == palette.id) return;
    HuntrColors.use(palette);
    appearance.value = palette;
    unawaited(devicePreferences?.saveThemeId(palette.id).catchError(
        (Object error) => debugPrint('Theme choice not saved: $error')));
  }

  /// How Explore lays people out (Settings → Appearance); remembered on
  /// this device.
  ExploreLayout _exploreLayout = ExploreLayout.standard;
  ExploreLayout get exploreLayout => _exploreLayout;
  set exploreLayout(ExploreLayout layout) {
    if (_exploreLayout == layout) return;
    _exploreLayout = layout;
    notifyListeners();
    unawaited(devicePreferences?.saveExploreLayout(layout.name).catchError(
        (Object error) => debugPrint('Explore layout not saved: $error')));
  }

  /// What this device remembers, when the app starts.
  Future<void> loadDevicePreferences() async {
    try {
      final show = await devicePreferences?.readShowVibeBanner();
      if (show != null && show != _showVibeBanner) {
        _showVibeBanner = show;
        notifyListeners();
      }
      final layout =
          ExploreLayout.fromName(await devicePreferences?.readExploreLayout());
      if (layout != null && layout != _exploreLayout) {
        _exploreLayout = layout;
        notifyListeners();
      }
      final themeId = await devicePreferences?.readThemeId();
      final palette = huntrPalettes.where((p) => p.id == themeId).firstOrNull;
      if (palette != null && palette.id != appearance.value.id) {
        HuntrColors.use(palette);
        appearance.value = palette;
      }
    } catch (error) {
      debugPrint('Device preferences not loaded: $error');
    }
  }

  /// Real people nearby, nearest first (from the backend). While null,
  /// Explore shows the sample profiles.
  List<Profile>? nearby;

  /// Where the next page of [nearby] starts; null when there is no more.
  int? nearbyNextOffset;

  void setNearby(List<Profile> people,
      {required int? nextOffset, bool append = false}) {
    nearby = [if (append) ...?nearby, ...people];
    nearbyNextOffset = nextOffset;
    notifyListeners();
  }

  /// A person nearby as loaded on their own (e.g. with all their photos).
  void updateNearbyPerson(Profile person) {
    final people = nearby;
    if (people == null) return;
    nearby = [for (final p in people) p.id == person.id ? person : p];
    notifyListeners();
  }

  List<Profile> get _explored => nearby ?? _profiles;

  List<Profile> get visibleProfiles => _explored.where(showsInExplore).toList();

  /// Explore shows them (list or map): not blocked, and matching my filters.
  bool showsInExplore(Profile p) =>
      !_blocked.contains(p.id) && _filters.matches(p);

  List<Profile> get favoriteProfiles => _profiles
      .where((p) => _favorites.contains(p.id) && !_blocked.contains(p.id))
      .toList();

  int get onlineCount =>
      _explored.where((p) => p.online && !_blocked.contains(p.id)).length;

  Profile? profileById(String id) {
    for (final p in [...?nearby, ..._profiles]) {
      if (p.id == id) return p;
    }
    return null;
  }

  bool isFavorite(String id) => _favorites.contains(id);

  void toggleFavorite(String id) {
    _favorites.contains(id) ? _favorites.remove(id) : _favorites.add(id);
    notifyListeners();
  }

  /// Back in the lists after an unblock (they show again once loaded).
  void unblock(String id) {
    if (_blocked.remove(id)) notifyListeners();
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

  /// Sends a chat request with the album I want to share. Nothing is shared until they approve;
  /// then both chosen albums are sent to each other and the chat opens.
  void sendRequest(Profile p, {String? note, String? albumId}) {
    if (connectionWith(p.id) != Connection.none) return;
    final n = note?.trim();
    _connections[p.id] = Connection.outgoing;
    _requests[p.id] = ChatRequest(
        profileId: p.id,
        sentAt: DateTime.now(),
        note: n == null || n.isEmpty ? null : n,
        albumId: albumId);
    notifyListeners();
    // Simulated: the other person approves after a moment and picks one of their albums.
    Timer(acceptDelay, () {
      if (connectionWith(p.id) != Connection.outgoing) return;
      final theirs =
          p.albums.isEmpty ? null : p.albums[_rnd.nextInt(p.albums.length)];
      _connect(p,
          iAccepted: false, myAlbum: myAlbumById(albumId), theirAlbum: theirs);
      _events.add('${p.name} accepted your request. Albums shared 📸');
    });
  }

  void cancelRequest(String id) {
    if (connectionWith(id) != Connection.outgoing) return;
    _connections.remove(id);
    _requests.remove(id);
    notifyListeners();
  }

  /// Approves their request, sharing [albumId] from my albums. Their chosen album comes to me.
  void acceptRequest(Profile p, {String? albumId}) {
    if (connectionWith(p.id) != Connection.incoming) return;
    final req = _requests[p.id];
    _connect(p,
        iAccepted: true,
        myAlbum: myAlbumById(albumId),
        theirAlbum: p.albumById(req?.albumId));
  }

  void declineRequest(String id) {
    if (connectionWith(id) != Connection.incoming) return;
    _connections.remove(id);
    _requests.remove(id);
    notifyListeners();
  }

  void _connect(Profile p,
      {required bool iAccepted, Album? myAlbum, Album? theirAlbum}) {
    final req = _requests.remove(p.id);
    _connections[p.id] = Connection.connected;
    final c = conversationWith(p);
    final now = DateTime.now();
    if (req?.note != null) {
      // the request note becomes the first message, from whoever asked
      c.messages.add(Message(
          id: 'm${_msgSeq++}',
          fromMe: !iAccepted,
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
    // both chosen albums are sent automatically: the requester's first, then the approver's
    final mine = myAlbum == null
        ? null
        : _albumMessage(fromMe: true, album: myAlbum, who: 'You', now: now);
    final theirs = theirAlbum == null
        ? null
        : _albumMessage(
            fromMe: false, album: theirAlbum, who: p.name, now: now);
    for (final m in iAccepted ? [theirs, mine] : [mine, theirs]) {
      if (m != null) c.messages.add(m);
    }
    if (!iAccepted && _openChat != p.id) c.unread++;
    notifyListeners();
  }

  Message _albumMessage(
          {required bool fromMe,
          required Album album,
          required String who,
          required DateTime now}) =>
      Message(
        id: 'm${_msgSeq++}',
        fromMe: fromMe,
        kind: MessageKind.album,
        text: '$who shared "${album.name}"',
        album: List.of(album.photos),
        albumName: album.name,
        sentAt: now,
      );

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
      final a = seeds[i].albums.first;
      c.messages.add(Message(
        id: 'm${_msgSeq++}',
        fromMe: false,
        kind: MessageKind.album,
        text: '${seeds[i].name} shared "${a.name}"',
        album: List.of(a.photos),
        albumName: a.name,
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
          note: notes[i],
          albumId: from[i].albums.first.id);
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
