import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'flows/guest_join.dart' show GuestStore;
import 'screens/session_gate.dart';
import 'services/agreement_service.dart';
import 'services/album_service.dart';
import 'services/explore_service.dart';
import 'services/changelog_service.dart';
import 'services/feedback_service.dart';
import 'services/nearby_service.dart';
import 'services/nearby_uploads.dart';
import 'services/story_service.dart';
import 'services/presence/presence_service.dart';
import 'services/location_service.dart';
import 'services/message_sound.dart';
import 'services/notification_sound.dart';
import 'services/messaging_service.dart';
import 'services/photo_cache/photo_cache_store.dart';
import 'services/photo_cache/photo_cache.dart';
import 'services/photo_service.dart';
import 'services/profile_service.dart';
import 'services/services_scope.dart';
import 'services/device_preferences.dart';
import 'services/session_service.dart';
import 'state/app_state.dart';
import 'state/block_state.dart';
import 'state/messaging_state.dart';
import 'state/tap_state.dart';
import 'services/block_service.dart';
import 'services/tap_service.dart';
import 'services/location_permission.dart';
import 'services/app_update.dart';
import 'services/rate_limit.dart';
import 'widgets/location_gate.dart';
import 'widgets/rate_limit_screen.dart';
import 'widgets/update_required_screen.dart';
import 'widgets/theme_follower.dart';
import 'widgets/video_taps_io.dart'
    if (dart.library.js_interop) 'widgets/video_taps_web.dart';
import 'services/push_notifications.dart';
import 'theme.dart';
import 'services/guest_chat_api.dart';
import 'state/guest_chats_state.dart';
import 'screens/guest_page.dart';

void main() {
  // before anything reads the device (saved preferences, secure storage)
  WidgetsFlutterBinding.ensureInitialized();
  // in a browser, a tap on a video reaches the app (not the video element)
  letAppTakeVideoTaps();
  // My own pictures, kept on the phone. Not in a browser: it caches images
  // itself, and downloading them for a cache there needs the bucket to allow
  // cross-origin requests - without that, every picture was fetched twice.
  final photoCache = kIsWeb
      ? null
      : PhotoCache(store: PhotoCacheStore.device('profile_photos'));
  final albumCache =
      kIsWeb ? null : PhotoCache(store: PhotoCacheStore.device('album_media'));
  late final MessagingState messaging;
  late final BlockState blocks;
  late final TapState taps;
  late final GuestChatsState guestChats;
  late final AppState state;
  late final NearbyUploads nearbyUploads;
  state = AppState(
    // A signed-out device keeps none of the user's photos or messages.
    onSessionEnd: () async {
      // this device stops getting the account's notifications (the token
      // is read now, before it's cleared)
      unawaited(PushNotifications.instance.stop(state.sessionToken));
      messaging.clear();
      blocks.clear();
      taps.clear();
      guestChats.clear();
      nearbyUploads.clear();
      await Future.wait([
        if (photoCache != null) photoCache.clear(),
        if (albumCache != null) albumCache.clear(),
      ]);
    },
    sampleAlbums: false, // mine come from the backend
    devicePreferences: const SecureDevicePreferences(),
  );
  unawaited(state.loadDevicePreferences());
  final sound = MessageSound(sound: () => state.notificationSound);
  // Android: a notification channel per sound, before any push needs one
  unawaited(NotificationSound.ensureChannels());
  messaging = MessagingState(
    service: const MessagingService(),
    token: () => state.sessionToken,
    playSound: sound.play,
    onSessionRejected: state.endSession,
  );
  blocks = BlockState(
      service: const BlockService(), token: () => state.sessionToken);
  taps = TapState(
      service: const TapService(),
      token: () => state.sessionToken,
      onSessionRejected: state.endSession);
  nearbyUploads =
      NearbyUploads(const NearbyService(), onSessionRejected: state.endSession);
  guestChats = GuestChatsState(
      api: GuestChatApi(),
      token: () => state.sessionToken,
      onSessionRejected: state.endSession);
  runApp(HuntrApp(
    state: state,
    updates: AppUpdateGate(),
    messaging: messaging,
    sessions: const SessionService(),
    profiles: const ProfileService(),
    agreements: const AgreementService(),
    photos: const PhotoService(),
    photoCache: photoCache,
    albums: const AlbumService(),
    albumCache: albumCache,
    explore: const ExploreService(),
    presence: PresenceService(),
    feedback: const FeedbackService(),
    changelog: const ChangelogService(),
    stories: const StoryService(),
    nearby: const NearbyService(),
    nearbyUploads: nearbyUploads,
    locationAccess: LocationAccess(const GeolocatorPermissions()),
    blocks: blocks,
    taps: taps,
    guestChats: guestChats,
    guestLinkCode: guestLinkCode(Uri.base),
  ));
}

class HuntrApp extends StatelessWidget {
  const HuntrApp({
    super.key,
    required this.state,
    this.sessions,
    this.profiles,
    this.agreements,
    this.photos,
    this.photoCache,
    this.albums,
    this.albumCache,
    this.explore,
    this.presence,
    this.feedback,
    this.changelog,
    this.stories,
    this.nearby,
    this.nearbyUploads,
    this.messaging,
    this.locate = locateDevice,
    this.locationAccess,
    this.blocks,
    this.taps,
    this.guestChats,
    this.guestLinkCode,
    this.updates,
  });

  final AppState state;

  /// Blocks an outdated app until it's updated (null: never checked, e.g.
  /// in tests).
  final AppUpdateGate? updates;

  /// Restores and saves the backend session. Null keeps it in memory only.
  final SessionService? sessions;

  /// Loads and saves the profile on the backend. Null keeps onboarding local.
  final ProfileService? profiles;

  /// The agreement new users accept before onboarding. Null skips it.
  final AgreementService? agreements;

  /// My profile photos on the backend. Null hides photo management.
  final PhotoService? photos;

  /// My profile photos saved on this device. Null shows them from the network.
  final PhotoCache? photoCache;

  /// My albums on the backend. Null keeps them on this device only.
  final AlbumService? albums;

  /// My album photos (and video thumbnails) saved on this device.
  final PhotoCache? albumCache;

  /// People nearby. Null shows the sample profiles.
  final ExploreService? explore;

  /// Keeps me shown as online while the app is open. Null: no presence.
  final PresenceService? presence;

  /// Feedback and suggestions (Settings > Support).
  final FeedbackService? feedback;

  /// What's new (Settings, and a sheet once for news).
  final ChangelogService? changelog;

  /// Stories (My Day).
  final StoryService? stories;

  /// Nearby's anonymous posts. Null: no Nearby tab content (tests).
  final NearbyService? nearby;

  /// Threads photos and videos on their way from this device.
  final NearbyUploads? nearbyUploads;

  /// My direct messages on the backend. Null keeps the sample chats.
  final MessagingState? messaging;

  final LocateDevice locate;

  /// Location permission: required to use the app (a full-screen notice
  /// covers it until allowed). Null doesn't check.
  final LocationAccess? locationAccess;

  /// Blocks between me and others (what screens show; the backend enforces
  /// them). Null: no blocking (tests, sample data).
  final BlockState? blocks;

  /// My Tap inbox, and tapping others. Null: no taps (tests, sample data).
  final TapState? taps;

  /// My guest link and guest chats. Null: none (tests, sample data).
  final GuestChatsState? guestChats;

  /// Opened as a guest link (huntr.online/g/<code>): its page first.
  final String? guestLinkCode;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MessagingScope(
        state: messaging,
        child: BlockScope(
          state: blocks,
          child: TapScope(
            state: taps,
            child: GuestChatsScope(
              state: guestChats,
              child: ServicesScope(
                profiles: profiles,
                agreements: agreements,
                sessions: sessions,
                photos: photos,
                photoCache: photoCache,
                albums: albums,
                albumCache: albumCache,
                explore: explore,
                presence: presence,
                feedback: feedback,
                changelog: changelog,
                stories: stories,
                nearby: nearby,
                nearbyUploads: nearbyUploads,
                child: ThemeFollower(
                  appearance: state.appearance,
                  builder: (context) => MaterialApp(
                    title: 'HUNTR',
                    debugShowCheckedModeBanner: false,
                    theme: buildHuntrTheme(),
                    // too many requests: one full-screen notice over everything
                    // too old: "Time to update" over everything, even that
                    builder: (context, child) {
                      final app = RateLimitOverlay(
                          gate: rateLimitGate, child: _locationGate(child!));
                      final updates = this.updates;
                      return updates == null
                          ? app
                          : UpdateGateOverlay(gate: updates, child: app);
                    },
                    home: _GuestLinkFirst(
                      code: guestLinkCode,
                      sessions: sessions,
                      app: SessionGate(
                        sessions: sessions,
                        profiles: profiles,
                        agreements: agreements,
                        locate: locate,
                        locationAccess: locationAccess,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Signed in and past the agreement (onboarding and the app itself): the
  /// location permission is required, over every screen.
  Widget _locationGate(Widget app) {
    final access = locationAccess;
    if (access == null) return app;
    return ListenableBuilder(
      listenable: state,
      builder: (context, child) => LocationGate(
        access: access,
        enforce: state.signedIn && (state.onboarded || state.agreementAccepted),
        // no location may be collected or sent without it
        onRevoked: () => messaging?.stopAllLiveSharing(),
        child: child!,
      ),
      child: app,
    );
  }
}

/// The code in a guest link's address (huntr.online/g/<code>), if it is one.
String? guestLinkCode(Uri uri) {
  final parts = uri.pathSegments;
  return parts.length == 2 && parts[0] == 'g' && parts[1].isNotEmpty
      ? parts[1]
      : null;
}

/// A guest link opened: its page, until they go to HUNTR itself (log in, or
/// join to keep talking), when the address becomes HUNTR's own.
/// A guest link (/g/<code>): its page for someone not on HUNTR. Someone
/// signed in here goes to HUNTR instead, where the link owner's anonymous
/// chat opens (as does someone who logs in from the page).
class _GuestLinkFirst extends StatefulWidget {
  const _GuestLinkFirst(
      {required this.code, required this.sessions, required this.app});

  final String? code;
  final SessionService? sessions;
  final Widget app;

  @override
  State<_GuestLinkFirst> createState() => _GuestLinkFirstState();
}

class _GuestLinkFirstState extends State<_GuestLinkFirst> {
  bool _left = false;

  /// Still looking for a saved session (signed in: no guest page).
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    final sessions = widget.sessions;
    if (widget.code != null && sessions != null) {
      _checking = true;
      unawaited(_signedInHere(sessions));
    }
  }

  Future<void> _signedInHere(SessionService sessions) async {
    String? token;
    try {
      token = await sessions.store.readToken();
    } catch (_) {}
    if (!mounted) return;
    if (token != null) return _leave();
    setState(() => _checking = false);
  }

  /// To HUNTR, where the link owner's anonymous chat opens once signed in.
  Future<void> _leave() async {
    await GuestStore.saveLink(widget.code!);
    SystemNavigator.routeInformationUpdated(uri: Uri.parse('/'));
    if (mounted) setState(() => _left = true);
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.code;
    if (code == null || _left) return widget.app;
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return GuestPage(code: code, onLeave: _leave);
  }
}
