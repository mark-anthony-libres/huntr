import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'profile_stats.dart';

export 'profile_stats.dart';

/// What someone is open to on Huntr. Shown as chips on profiles and used as a filter.
enum LookingFor {
  chat('Chat', Icons.chat_bubble_outline),
  friends('Friends', Icons.people_outline),
  dates('Dates', Icons.local_cafe_outlined),
  networking('Networking', Icons.work_outline),
  relationship('Relationship', Icons.favorite_border);

  const LookingFor(this.label, this.icon);
  final String label;
  final IconData icon;

  /// The choices matching backend values such as "chat"; unknown names are ignored.
  static Set<LookingFor> fromNames(Iterable<String> names) => {
        for (final choice in values)
          if (names.contains(choice.name)) choice,
      };
}

/// The one sexual position a profile shows (none: "Do not show").
enum SexualPosition {
  top('Top', 'top'),
  bottom('Bottom', 'bottom'),
  versatile('Versatile', 'versatile'),
  versBottom('Vers Bottom', 'vers_bottom'),
  versTop('Vers Top', 'vers_top'),
  side('Side', 'side');

  const SexualPosition(this.label, this.apiName);
  final String label;

  /// The backend's value, e.g. "vers_top".
  final String apiName;

  /// From the backend's value; null (not shown) for null or unknown ones.
  static SexualPosition? parse(String? apiName) {
    for (final p in values) {
      if (p.apiName == apiName) return p;
    }
    return null;
  }
}

/// A point on the map, in degrees.
class GeoPoint {
  const GeoPoint({required this.latitude, required this.longitude});
  final double latitude;
  final double longitude;
}

/// What the user entered during onboarding.
class OnboardingAnswers {
  const OnboardingAnswers({
    required this.displayName,
    required this.age,
    required this.location,
    required this.lookingFor,
  });

  /// Optional; empty means no display name.
  final String displayName;
  final int age;
  final GeoPoint location;
  final Set<LookingFor> lookingFor;
}

/// What the user submits from Edit profile. [lookingFor] is the complete
/// selection and replaces the saved one.
class ProfileEdit {
  const ProfileEdit({
    required this.displayName,
    required this.bio,
    required this.age,
    required this.lookingFor,
    this.stats,
  });

  /// The stats to save (null: leave them as they are).
  final ProfileStats? stats;

  /// Optional; empty means no display name.
  final String displayName;

  /// Optional; empty means no bio.
  final String bio;
  final int age;
  final Set<LookingFor> lookingFor;
}

/// A picture stored on the backend (in S3) that this device may cache: kept
/// by [id] (stable), downloaded from [imageUrl] (temporary).
abstract interface class StoredPhoto {
  int get id;
  String get imageUrl;
  int get width;
  int get height;
}

/// One of my profile photos, stored on the backend (image in S3, details in
/// the database). The links are temporary; reload the list to refresh them.
class ProfilePhoto implements StoredPhoto {
  const ProfilePhoto({
    required this.id,
    required this.url,
    required this.isDefault,
    required this.width,
    required this.height,
  });

  factory ProfilePhoto.fromJson(Map<String, dynamic> json) => ProfilePhoto(
        id: json['id'] as int,
        url: json['url'] as String,
        isDefault: json['is_default'] as bool,
        width: json['width'] as int,
        height: json['height'] as int,
      );

  @override
  final int id;

  /// The saved (cropped) photo - the only stored copy.
  final String url;
  final bool isDefault;
  @override
  final int width;
  @override
  final int height;

  @override
  String get imageUrl => url;
}

/// A photo or video in one of my albums, stored on the backend. For a video,
/// the picture shown (and cached) is its thumbnail; the video itself plays
/// from [url].
class StoredAlbumItem implements StoredPhoto {
  const StoredAlbumItem({
    required this.id,
    required this.isVideo,
    required this.url,
    required this.width,
    required this.height,
    this.thumbnailUrl,
    this.durationMs,
  });

  factory StoredAlbumItem.fromJson(Map<String, dynamic> json) =>
      StoredAlbumItem(
        id: json['id'] as int,
        isVideo: json['type'] == 'video',
        url: json['url'] as String,
        thumbnailUrl: json['thumbnail_url'] as String?,
        width: json['width'] as int,
        height: json['height'] as int,
        durationMs: json['duration_ms'] as int?,
      );

  @override
  final int id;
  final bool isVideo;
  final String url;
  final String? thumbnailUrl;
  @override
  final int width;
  @override
  final int height;
  final int? durationMs;

  @override
  String get imageUrl => isVideo ? thumbnailUrl ?? url : url;
}

/// One picture in someone's private album. My albums hold [stored] photos
/// and videos from the backend; other people's (sample) albums are still
/// generated art (a hue and a subject).
class AlbumPhoto {
  const AlbumPhoto(
      {required this.id,
      required this.hue,
      required this.subject,
      this.stored});

  /// One of my stored album items.
  factory AlbumPhoto.stored(StoredAlbumItem item) => AlbumPhoto(
      id: 'album-item-${item.id}',
      hue: 0,
      subject: PhotoSubject.selfie,
      stored: item);

  final String id;
  final double hue;
  final PhotoSubject subject;
  final StoredAlbumItem? stored;
}

enum PhotoSubject {
  selfie('Selfie', Icons.face_retouching_natural),
  beach('Beach day', Icons.beach_access),
  gym('Gym', Icons.fitness_center),
  coffee('Coffee', Icons.local_cafe),
  hike('Hike', Icons.landscape),
  nightOut('Night out', Icons.nightlife),
  pet('My pet', Icons.pets),
  travel('Travel', Icons.flight_takeoff),
  food('Food trip', Icons.ramen_dining);

  const PhotoSubject(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Where two people stand. Chatting is only possible once [connected].
enum Connection {
  none,

  /// I sent a request and I'm waiting for them.
  outgoing,

  /// They sent me a request.
  incoming,
  connected,
}

/// What my backend albums may hold, as set by the backend.
class AlbumLimits {
  const AlbumLimits({
    required this.maxAlbums,
    required this.maxItems,
    required this.maxPhotoBytes,
    required this.maxVideoBytes,
    required this.maxVideoSeconds,
    this.maxNameLength,
  });

  final int maxAlbums;

  /// Photos and videos together, per album.
  final int maxItems;
  final int maxPhotoBytes;
  final int maxVideoBytes;
  final int maxVideoSeconds;

  /// The longest album name, as set by the backend (null: not known).
  final int? maxNameLength;
}

/// A named, private collection of photos. Never shown on a profile; only sent into a chat when
/// its owner picks it while sending or accepting a chat request.
class Album {
  Album({required this.id, required this.name, List<AlbumPhoto>? photos})
      : photos = photos ?? [];
  final String id;
  String name;
  final List<AlbumPhoto> photos;

  /// What's in it, e.g. "3 photos · 1 video", or "Empty".
  String get contentsLabel {
    final videos = photos.where((p) => p.stored?.isVideo == true).length;
    final pictures = photos.length - videos;
    String count(int n, String what) => '$n $what${n == 1 ? '' : 's'}';
    return [
      if (pictures > 0) count(pictures, 'photo'),
      if (videos > 0) count(videos, 'video'),
    ].join(' · ').ifEmpty('Empty');
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

class ChatRequest {
  const ChatRequest(
      {required this.profileId, required this.sentAt, this.note, this.albumId});
  final String profileId;
  final DateTime sentAt;
  final String? note;

  /// The album the sender chose to share. Both people's chosen albums are sent on approval.
  final String? albumId;
}

/// The generated avatar's colour for a user id: the same on every screen
/// and for every viewer (my preview included).
double avatarHueFor(int userId) => (userId * 47 % 360).toDouble();

class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.age,
    required this.distanceKm,
    required this.bio,
    required this.interests,
    required this.lookingFor,
    required this.online,
    required this.lastActive,
    required this.hue,
    this.pronouns,
    this.heightCm,
    this.verified = false,
    this.photos = const [],
    this.photoUrls = const [],
    this.albums = const [],
    this.backendId,
    this.distanceHidden = false,
    this.isNew = false,
    this.blockedByMe = false,
    this.blockedMe = false,
    this.ageHidden = false,
    this.stats = const ProfileStats(),
    this.anonymousAvatar,
    this.unmatched = false,
    this.hasStory = false,
    this.storySeen = false,
  });

  /// Someone anonymous to me (the sender of an anonymous conversation): only
  /// their anonymous name, animal and whether they're online - no user id,
  /// so nothing that needs one (their profile, a direct message) can be
  /// reached through it.
  factory Profile.anonymous(int conversationId, Map<String, dynamic> json) {
    final blocked = json['blocked'] as Map<String, dynamic>?;
    return Profile(
      id: 'anonymous-$conversationId',
      name: (json['display_name'] as String?)?.trim() ?? 'Anonymous',
      age: 0,
      ageHidden: true,
      distanceKm: 0,
      distanceHidden: true,
      bio: '',
      interests: const [],
      lookingFor: const {},
      online: const {'online', 'stale'}.contains(json['presence']),
      lastActive: DateTime.now(),
      hue: 24,
      anonymousAvatar: json['anonymous_avatar'] as String? ?? 'fox',
      blockedByMe: blocked?['by_me'] == true,
      blockedMe: blocked?['me'] == true,
    );
  }

  /// A real person from the backend (Explore nearby), by user id. Sample
  /// profiles have none.
  factory Profile.nearby(Map<String, dynamic> json) {
    final id = json['id'] as int;
    final distance = (json['distance_km'] as num?)?.toDouble();
    final lastSeen = json['last_seen_at'] as String?;
    return Profile(
      id: 'user-$id',
      backendId: id,
      // No alias, no name: only the age is shown.
      name: (json['display_name'] as String?)?.trim() ?? '',
      isNew: json['is_new'] as bool? ?? false,
      // null: they hide their age
      age: json['age'] as int? ?? 0,
      ageHidden: json['age'] == null,
      distanceKm: distance ?? 0,
      distanceHidden: distance == null,
      bio: json['bio'] as String? ?? '',
      interests: const [],
      lookingFor: {
        for (final choice in json['looking_for'] as List<dynamic>? ?? const [])
          for (final option in LookingFor.values)
            if (option.name == choice) option,
      },
      // Connected counts as online, in front ("online") or in the background
      // ("stale"); only a closed app or lost connection is offline.
      online: const {'online', 'stale'}.contains(json['presence']),
      lastActive: lastSeen == null
          ? DateTime.now()
          : DateTime.parse(lastSeen).toLocal(),
      hue: avatarHueFor(id),
      // All their photos when loaded one by one; the main one in lists.
      photoUrls: json['photo_urls'] != null
          ? (json['photo_urls'] as List<dynamic>).cast<String>()
          : [if (json['photo_url'] != null) json['photo_url'] as String],
      blockedByMe: (json['blocked'] as Map<String, dynamic>?)?['by_me'] == true,
      blockedMe: (json['blocked'] as Map<String, dynamic>?)?['me'] == true,
      stats: ProfileStats.fromJson(json),
      unmatched: json['unmatched'] == true,
      hasStory: json['has_story'] == true,
      storySeen: json['story_seen'] == true,
    );
  }

  final int? backendId;

  /// Shown as this cartoon animal (wolf, fox, ...): they're anonymous to me.
  final String? anonymousAvatar;
  bool get isAnonymous => anonymousAvatar != null;

  /// Opened from my Unmatched Users list: no Message, only removing them
  /// from the list.
  final bool unmatched;

  /// They chose not to show their distance (still listed in distance order).
  final bool distanceHidden;

  /// Joined in the last week (a "New" badge).
  final bool isNew;

  /// They have a story up (a ring on their photo).
  final bool hasStory;

  /// I've watched all of it (the ring turns grey).
  final bool storySeen;

  /// This person with their story state changed (e.g. once I watched it).
  Profile copyWith({bool? hasStory, bool? storySeen}) => Profile(
        id: id,
        name: name,
        age: age,
        distanceKm: distanceKm,
        bio: bio,
        interests: interests,
        lookingFor: lookingFor,
        online: online,
        lastActive: lastActive,
        hue: hue,
        pronouns: pronouns,
        heightCm: heightCm,
        verified: verified,
        photos: photos,
        photoUrls: photoUrls,
        albums: albums,
        backendId: backendId,
        distanceHidden: distanceHidden,
        isNew: isNew,
        blockedByMe: blockedByMe,
        blockedMe: blockedMe,
        ageHidden: ageHidden,
        stats: stats,
        anonymousAvatar: anonymousAvatar,
        unmatched: unmatched,
        hasStory: hasStory ?? this.hasStory,
        storySeen: storySeen ?? this.storySeen,
      );

  /// A block between us (as the chat list knows it): I block them, or they
  /// block me. Nothing can be sent either way while either is true.
  final bool blockedByMe;
  final bool blockedMe;

  /// They hide their age (Show Age off): [age] means nothing then.
  final bool ageHidden;

  /// Their stats (height, weight, body type, position, ...), as far as set.
  final ProfileStats stats;

  /// The position they show (null: they chose not to show one).
  SexualPosition? get sexualPosition => stats.sexualPosition;

  /// "Sam", or "22" for someone without a name ("Someone" when the age is
  /// hidden too).
  String get shortName => name.isNotEmpty
      ? name
      : ageHidden
          ? 'Someone'
          : '$age';

  /// "Sam, 22", or just "22" for someone without a name.
  String get nameAndAge => ageHidden
      ? name
      : name.isEmpty
          ? '$age'
          : '$name, $age';

  final String id;
  final String name;
  final int age;
  final double distanceKm;
  final String bio;
  final List<String> interests;
  final Set<LookingFor> lookingFor;
  final bool online;
  final DateTime lastActive;

  /// Base hue (0-360) for this person's generated avatar.
  final double hue;
  final String? pronouns;
  final int? heightCm;
  final bool verified;

  /// Real photos, by link (my own profile); used instead of [photos].
  final List<String> photoUrls;

  /// Public profile pictures, shown on the profile. The first one is the main picture.
  final List<AlbumPhoto> photos;

  /// Private albums, separate from the profile.
  final List<Album> albums;

  Album? albumById(String? id) {
    for (final a in albums) {
      if (a.id == id) return a;
    }
    return null;
  }

  String get initials {
    if (name.trim().isEmpty) return '';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  String get distanceLabel {
    if (distanceHidden) return 'Distance hidden';
    // Exact, as decided: metres under 1 km, otherwise km to 2 decimals.
    if (distanceKm < 1) return '${(distanceKm * 1000).round()} m away';
    return '${distanceKm.toStringAsFixed(2)} km away';
  }

  String activeLabel(DateTime now) {
    if (online) return 'Online now';
    // no last-seen time for someone anonymous
    if (isAnonymous) return 'Offline';
    final d = now.difference(lastActive);
    // A time ahead of this device's clock (clock skew) is just now.
    if (d.inMinutes < 1) return 'Active just now';
    if (d.inMinutes < 60) return 'Active ${d.inMinutes}m ago';
    if (d.inHours < 24) return 'Active ${d.inHours}h ago';
    return 'Active ${d.inDays}d ago';
  }
}

enum MessageStatus { sending, sent, read, failed }

enum MessageKind {
  text,

  /// An album shared into the chat. [Message.album] holds the photos.
  album,

  /// A centered notice such as "Chat request accepted".
  notice,
}

class Message {
  Message({
    required this.id,
    required this.fromMe,
    required this.text,
    required this.sentAt,
    this.status = MessageStatus.sent,
    this.kind = MessageKind.text,
    this.album = const [],
    this.albumName,
  });

  final String id;
  final bool fromMe;
  final String text;
  final DateTime sentAt;
  final MessageKind kind;
  final List<AlbumPhoto> album;
  final String? albumName;
  MessageStatus status;
}

class Conversation {
  Conversation(
      {required this.profile, List<Message>? messages, this.unread = 0})
      : messages = messages ?? [];

  final Profile profile;
  final List<Message> messages;
  int unread;
  bool typing = false;

  Message? get last => messages.isEmpty ? null : messages.last;
}

/// Explore filters. Everything is optional; an empty filter shows everyone.
/// How Explore lays people out, chosen in Settings → Appearance (on this
/// device): how many across on a phone, and what each card says.
enum ExploreLayout {
  /// One per row: photo, name, bio and what they're looking for.
  one(1, 'Detailed', "Name, age, bio and what they're looking for",
      Icons.view_agenda_outlined),

  /// Name, age and how far.
  two(2, 'Comfortable', 'Name, age and distance', Icons.grid_view_rounded),

  /// Just the name, small.
  three(3, 'Compact', 'Just the name', Icons.apps_rounded),

  /// Photos only.
  four(4, 'Photos only', 'No names, more people at once',
      Icons.view_comfy_outlined);

  const ExploreLayout(this.columns, this.label, this.description, this.icon);

  /// Across, on a phone (more on wider screens).
  final int columns;
  final String label;
  final String description;
  final IconData icon;

  /// Until one is chosen: 2 across on the web (name, age and distance on
  /// wide screens), 3 on phones.
  static ExploreLayout get standard =>
      kIsWeb ? ExploreLayout.two : ExploreLayout.three;

  static ExploreLayout? fromName(String? name) =>
      values.where((layout) => layout.name == name).firstOrNull;
}

class ExploreFilters {
  const ExploreFilters({
    this.onlineOnly = false,
    this.maxDistanceKm,
    this.ageRange = const RangeValues(18, 60),
    this.lookingFor = const {},
    this.query = '',
  });

  final bool onlineOnly;
  final double? maxDistanceKm;
  final RangeValues ageRange;
  final Set<LookingFor> lookingFor;
  final String query;

  bool get isDefault =>
      !onlineOnly &&
      maxDistanceKm == null &&
      ageRange.start <= 18 &&
      ageRange.end >= 60 &&
      lookingFor.isEmpty &&
      query.isEmpty;

  ExploreFilters copyWith({
    bool? onlineOnly,
    double? maxDistanceKm,
    bool clearDistance = false,
    RangeValues? ageRange,
    Set<LookingFor>? lookingFor,
    String? query,
  }) {
    return ExploreFilters(
      onlineOnly: onlineOnly ?? this.onlineOnly,
      maxDistanceKm:
          clearDistance ? null : (maxDistanceKm ?? this.maxDistanceKm),
      ageRange: ageRange ?? this.ageRange,
      lookingFor: lookingFor ?? this.lookingFor,
      query: query ?? this.query,
    );
  }

  bool matches(Profile p) {
    if (onlineOnly && !p.online) return false;
    // A hidden distance never counts as near (nor reveals anything).
    if (maxDistanceKm != null &&
        (p.distanceHidden || p.distanceKm > maxDistanceKm!)) {
      return false;
    }
    // a hidden age is never filtered on (nor revealed)
    if (!p.ageHidden && (p.age < ageRange.start || p.age > ageRange.end)) {
      return false;
    }
    if (lookingFor.isNotEmpty &&
        p.lookingFor.intersection(lookingFor).isEmpty) {
      return false;
    }
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      final hit = p.name.toLowerCase().contains(q) ||
          p.bio.toLowerCase().contains(q) ||
          p.interests.any((i) => i.toLowerCase().contains(q));
      if (!hit) return false;
    }
    return true;
  }
}
