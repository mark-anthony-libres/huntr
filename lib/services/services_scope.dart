import 'package:flutter/widgets.dart';

import 'agreement_service.dart';
import 'album_service.dart';
import 'explore_service.dart';
import 'feedback_service.dart';
import 'nearby_service.dart';
import 'story_service.dart';
import 'presence/presence_service.dart';
import 'photo_cache/photo_cache.dart';
import 'photo_service.dart';
import 'profile_service.dart';
import 'session_service.dart';

/// Makes backend services available to screens below the app's root.
class ServicesScope extends InheritedWidget {
  const ServicesScope({
    super.key,
    required this.profiles,
    required this.agreements,
    this.sessions,
    this.photos,
    this.photoCache,
    this.albums,
    this.albumCache,
    this.explore,
    this.presence,
    this.feedback,
    this.stories,
    this.nearby,
    required super.child,
  });

  /// Null when the app runs without a backend (e.g. widget tests).
  final ProfileService? profiles;
  final AgreementService? agreements;
  final SessionService? sessions;
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

  /// Feedback and suggestions. Null hides Settings' Support rows.
  final FeedbackService? feedback;

  /// Stories (My Day). Null hides them.
  final StoryService? stories;

  /// Nearby's anonymous posts. Null: no Nearby (tests, sample data).
  final NearbyService? nearby;

  static ServicesScope? _of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ServicesScope>();

  static ProfileService? profilesOf(BuildContext context) =>
      _of(context)?.profiles;

  static AgreementService? agreementsOf(BuildContext context) =>
      _of(context)?.agreements;

  static SessionService? sessionsOf(BuildContext context) =>
      _of(context)?.sessions;

  static PhotoService? photosOf(BuildContext context) => _of(context)?.photos;

  /// The device cache of one collection (my profile photos by default).
  static PhotoCache? photoCacheOf(BuildContext context,
      [PhotoCollection collection = PhotoCollection.profile]) {
    final scope = _of(context);
    return switch (collection) {
      PhotoCollection.profile => scope?.photoCache,
      PhotoCollection.album => scope?.albumCache,
    };
  }

  static AlbumService? albumsOf(BuildContext context) => _of(context)?.albums;

  static ExploreService? exploreOf(BuildContext context) =>
      _of(context)?.explore;

  static PresenceService? presenceOf(BuildContext context) =>
      _of(context)?.presence;

  static FeedbackService? feedbackOf(BuildContext context) =>
      _of(context)?.feedback;

  static StoryService? storiesOf(BuildContext context) => _of(context)?.stories;

  static NearbyService? nearbyOf(BuildContext context) => _of(context)?.nearby;

  @override
  bool updateShouldNotify(ServicesScope oldWidget) =>
      profiles != oldWidget.profiles ||
      agreements != oldWidget.agreements ||
      sessions != oldWidget.sessions ||
      photos != oldWidget.photos ||
      photoCache != oldWidget.photoCache ||
      albums != oldWidget.albums ||
      albumCache != oldWidget.albumCache ||
      explore != oldWidget.explore ||
      feedback != oldWidget.feedback ||
      stories != oldWidget.stories ||
      nearby != oldWidget.nearby ||
      presence != oldWidget.presence;
}
