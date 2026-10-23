import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'screens/session_gate.dart';
import 'services/agreement_service.dart';
import 'services/album_service.dart';
import 'services/explore_service.dart';
import 'services/feedback_service.dart';
import 'services/story_service.dart';
import 'services/presence/presence_service.dart';
import 'services/location_service.dart';
import 'services/message_sound.dart';
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
import 'theme.dart';

void main() {
  // before anything reads the device (saved preferences, secure storage)
  WidgetsFlutterBinding.ensureInitialized();
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
  final state = AppState(
    // A signed-out device keeps none of the user's photos or messages.
    onSessionEnd: () async {
      messaging.clear();
      blocks.clear();
      taps.clear();
      await Future.wait([
        if (photoCache != null) photoCache.clear(),
        if (albumCache != null) albumCache.clear(),
      ]);
    },
    sampleAlbums: false, // mine come from the backend
    devicePreferences: const SecureDevicePreferences(),
  );
  unawaited(state.loadDevicePreferences());
  final sound = MessageSound();
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
    stories: const StoryService(),
    locationAccess: LocationAccess(const GeolocatorPermissions()),
    blocks: blocks,
    taps: taps,
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
    this.stories,
    this.messaging,
    this.locate = locateDevice,
    this.locationAccess,
    this.blocks,
    this.taps,
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

  /// Stories (My Day).
  final StoryService? stories;

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
              stories: stories,
              child: MaterialApp(
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
                home: SessionGate(
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
