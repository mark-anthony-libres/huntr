import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'rate_limit.dart';

class BackendException implements Exception {
  const BackendException(this.message);
  final String message;
}

/// What the backend answers (409) for anything between two people in a
/// block; shown as it is.
const blockedByThemMessage = 'You are blocked by this person';
const blockedByMeMessage = 'You blocked this person.';

/// The other person blocks me ([byMe] false), or I block them.
class BlockedException extends BackendException {
  const BlockedException({required this.byMe})
      : super(byMe ? blockedByMeMessage : blockedByThemMessage);

  final bool byMe;
}

/// The backend refused the request for now (HTTP 429): too many requests
/// in a short time. [rateLimitGate] shows the full-screen notice.
class RateLimitedException extends BackendException {
  const RateLimitedException(this.retryAfter)
      : super('You’re doing that too fast. Please wait a few minutes '
            'and try again.');

  final Duration retryAfter;
}

/// Reports a 429 to [rateLimitGate] and throws; anything else passes.
void _checkRateLimit(http.Response response) {
  if (response.statusCode != 429) return;
  final wait = retryAfterOf(response);
  rateLimitGate.limited(wait);
  throw RateLimitedException(wait);
}

/// A chat photo or video that has expired (or whose file is gone): it can
/// no longer be opened.
class MediaExpiredException extends BackendException {
  const MediaExpiredException(super.message);
}

/// The backend no longer accepts the session token; the user must sign in again.
class SessionRejectedException extends BackendException {
  const SessionRejectedException()
      : super('Your session has expired. Please sign in again.');
}

/// The backend rejected some fields; [fieldErrors] maps field name to message.
class ProfileValidationException extends BackendException {
  const ProfileValidationException(this.fieldErrors)
      : super('Please fix the highlighted fields.');
  final Map<String, String> fieldErrors;
}

/// Profile form limits, set by the backend's settings.
class ProfileConfig {
  const ProfileConfig({
    required this.bioMaxLength,
    required this.displayNameMaxLength,
    required this.minAge,
    required this.maxAge,
  });

  factory ProfileConfig.fromJson(Map<String, dynamic> json) => ProfileConfig(
        bioMaxLength: json['bio_max_length'] as int,
        displayNameMaxLength: json['display_name_max_length'] as int,
        minAge: json['min_age'] as int,
        maxAge: json['max_age'] as int,
      );

  final int bioMaxLength;
  final int displayNameMaxLength;
  final int minAge;
  final int maxAge;
}

/// The signed-in user's profile as stored by the backend.
class MyProfile {
  const MyProfile({
    this.id,
    this.isNew = false,
    required this.name,
    required this.displayName,
    this.bio,
    required this.age,
    required this.latitude,
    required this.longitude,
    required this.lookingFor,
    required this.onboarded,
    this.privacy = const PrivacySettings(),
    this.sexualPosition,
    this.stats = const ProfileStats(),
    this.anonymousName,
  });

  factory MyProfile.fromJson(Map<String, dynamic> json) => MyProfile(
        id: json['id'] as int?,
        isNew: json['is_new'] as bool? ?? false,
        name: json['name'] as String?,
        displayName: json['display_name'] as String?,
        bio: json['bio'] as String?,
        age: json['age'] as int?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        lookingFor:
            (json['looking_for'] as List<dynamic>? ?? const []).cast<String>(),
        onboarded: json['onboarded'] as bool? ?? false,
        privacy: PrivacySettings.fromJson(json),
        sexualPosition: json['sexual_position'] as String?,
        stats: ProfileStats.fromJson(json),
        anonymousName: json['anonymous_name'] == null
            ? null
            : AnonymousName.fromJson(
                json['anonymous_name'] as Map<String, dynamic>),
      );

  /// My anonymous name in anonymous chats and Threads (only I see it's me).
  final AnonymousName? anonymousName;

  /// Account name from Google.
  /// My user id (null from older backends).
  /// The sexual position shown (backend value; null: not shown).
  final String? sexualPosition;

  /// All my stats (with Show Age and my units).
  final ProfileStats stats;

  final int? id;

  /// Joined in the last week (others see a "New" badge).
  final bool isNew;
  final String? name;
  final String? displayName;
  final String? bio;
  final int? age;
  final double? latitude;
  final double? longitude;
  final List<String> lookingFor;

  /// True once age and location are saved.
  final bool onboarded;

  final PrivacySettings privacy;
}

/// What the user lets others see. Both default to visible.
class PrivacySettings {
  const PrivacySettings(
      {this.showOnline = true,
      this.showDistance = true,
      this.showOnMap = true,
      this.anonymousMessaging = true,
      this.notifyTaps = true,
      this.notifyMessages = true,
      this.notifyStoryReplies = true});

  factory PrivacySettings.fromJson(Map<String, dynamic> json) =>
      PrivacySettings(
        showOnline: json['show_online'] as bool? ?? true,
        showDistance: json['show_distance'] as bool? ?? true,
        showOnMap: json['show_on_map'] as bool? ?? true,
        anonymousMessaging:
            json['anonymous_messaging_enabled'] as bool? ?? true,
        notifyTaps: json['notify_taps'] as bool? ?? true,
        notifyMessages: json['notify_messages'] as bool? ?? true,
        notifyStoryReplies: json['notify_story_replies'] as bool? ?? true,
      );

  final bool showOnline;
  final bool showDistance;

  /// Shown on Explore's map (blurred; only while showing my distance too).
  final bool showOnMap;

  /// I may send anonymous messages (Settings > Anonymous messaging).
  final bool anonymousMessaging;

  /// Push notifications for each kind (Settings > Notifications).
  final bool notifyTaps;
  final bool notifyMessages;
  final bool notifyStoryReplies;
}

/// The signed-in Huntr account returned by the backend.
class BackendAccount {
  const BackendAccount({required this.token, required this.name});
  final String token;
  final String? name;
}

Uri _endpoint(String backendUrl, String path) =>
    Uri.parse('${backendUrl.replaceAll(RegExp(r'/+$'), '')}$path');

/// Exchanges a Google ID token for a Huntr session (POST {backendUrl}/google/login).
Future<BackendAccount> signInToBackendWithGoogle({
  required String backendUrl,
  required String idToken,
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient.post(
      _endpoint(backendUrl, '/google/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id_token': idToken}),
    );
    _checkRateLimit(response);
    if (response.statusCode == 403) {
      throw const BackendException('This account has been deactivated.');
    }
    if (response.statusCode != 200) {
      throw BackendException(
          'Huntr rejected the Google sign-in (${response.statusCode}).');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final user = body['user'] as Map<String, dynamic>?;
    return BackendAccount(
        token: body['token'] as String, name: user?['name'] as String?);
  } finally {
    if (client == null) httpClient.close();
  }
}

/// Asks the backend whether [token] still belongs to an active session
/// (GET {backendUrl}/auth/verify). Throws [BackendException] when the
/// backend can't give an answer, e.g. it is unreachable.
Future<bool> isBackendSessionValid({
  required String backendUrl,
  required String token,
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient.get(
      _endpoint(backendUrl, '/auth/verify'),
      headers: {'Authorization': 'Bearer $token'},
    );
    _checkRateLimit(response);
    return switch (response.statusCode) {
      200 => true,
      401 || 403 => false,
      _ => throw BackendException(
          'Could not check your Huntr session (${response.statusCode}).'),
    };
  } on http.ClientException {
    throw const BackendException('Could not reach the Huntr server.');
  } finally {
    if (client == null) httpClient.close();
  }
}

/// Ends this session on the backend (POST {backendUrl}/auth/logout): the
/// token stops working everywhere. Throws [BackendException] when the
/// backend can't be reached.
Future<void> logOutOfBackend({
  required String backendUrl,
  required String token,
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();
  try {
    // a bad connection mustn't keep the user from logging out
    final response = await httpClient.post(
      _endpoint(backendUrl, '/auth/logout'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 10),
        onTimeout: () => throw const BackendException(
            'The Huntr server took too long to answer.'));
    _checkRateLimit(response);
    // 401: the session had already ended, which is what was wanted
    if (response.statusCode != 200 && response.statusCode != 401) {
      throw BackendException('Logging out failed (${response.statusCode}).');
    }
  } on http.ClientException {
    throw const BackendException('Could not reach the Huntr server.');
  } finally {
    if (client == null) httpClient.close();
  }
}

/// The build every app must have, and where to get it (GET .../app/version).
class AppRelease {
  const AppRelease(
      {required this.latestBuild, this.playStoreUrl, this.appStoreUrl});

  factory AppRelease.fromJson(Map<String, dynamic> json) => AppRelease(
        latestBuild: json['latest_build'] as int? ?? 0,
        playStoreUrl: json['play_store_url'] as String?,
        appStoreUrl: json['app_store_url'] as String?,
      );

  /// Older builds must update first (0: no requirement).
  final int latestBuild;
  final String? playStoreUrl;
  final String? appStoreUrl;
}

/// GET .../app/version. Public: asked before signing in too.
Future<AppRelease> fetchAppRelease(
    {required String backendUrl, http.Client? client}) async {
  final httpClient = client ?? http.Client();
  try {
    final response =
        await httpClient.get(_endpoint(backendUrl, '/app/version'));
    if (response.statusCode != 200) {
      throw BackendException(
          'The app version could not be checked (${response.statusCode}).');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return AppRelease.fromJson(body['data'] as Map<String, dynamic>);
  } on http.ClientException {
    throw const BackendException('Could not reach the Huntr server.');
  } finally {
    if (client == null) httpClient.close();
  }
}

/// The terms new users must accept, as Markdown (GET {backendUrl}/agreement).
/// Public: no session token needed.
Future<String> fetchAgreement({
  required String backendUrl,
  http.Client? client,
}) =>
    _fetchMarkdown(backendUrl, '/agreement', 'The agreement', client);

/// The Community Guidelines, as Markdown (GET .../agreement/guidelines).
/// Public: no session token needed.
Future<String> fetchCommunityGuidelines({
  required String backendUrl,
  http.Client? client,
}) =>
    _fetchMarkdown(backendUrl, '/agreement/guidelines',
        'The Community Guidelines', client);

Future<String> _fetchMarkdown(
    String backendUrl, String path, String what, http.Client? client) async {
  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient.get(_endpoint(backendUrl, path));
    _checkRateLimit(response);
    if (response.statusCode != 200) {
      throw BackendException(
          '$what could not be loaded (${response.statusCode}).');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['data'] as Map<String, dynamic>)['content'] as String;
  } on http.ClientException {
    throw const BackendException('Could not reach the Huntr server.');
  } finally {
    if (client == null) httpClient.close();
  }
}

/// Declines the agreement, which deactivates the account
/// (POST {backendUrl}/agreement/decline).
Future<void> declineAgreement({
  required String backendUrl,
  required String token,
  http.Client? client,
}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _endpoint(backendUrl, '/agreement/decline'),
          headers: _authorization(token)),
      (_) {},
    );

/// Permanently deletes the signed-in user's account and data
/// (DELETE {backendUrl}/profile/me).
Future<void> deleteMyAccount({
  required String backendUrl,
  required String token,
  http.Client? client,
}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.delete(_endpoint(backendUrl, '/profile/me'),
          headers: _authorization(token)),
      (_) {},
    );

/// Loads the signed-in user's profile (GET {backendUrl}/profile/me).
Future<MyProfile> fetchMyProfile({
  required String backendUrl,
  required String token,
  http.Client? client,
}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(_endpoint(backendUrl, '/profile/me'),
          headers: _authorization(token)),
      MyProfile.fromJson,
    );

/// Saves the onboarding answers (PUT {backendUrl}/profile/me/onboarding).
Future<MyProfile> saveMyOnboarding({
  required String backendUrl,
  required String token,
  required String? displayName,
  required int age,
  required double latitude,
  required double longitude,
  required List<String> lookingFor,
  http.Client? client,
}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.put(
        _endpoint(backendUrl, '/profile/me/onboarding'),
        headers: {..._authorization(token), 'Content-Type': 'application/json'},
        body: jsonEncode({
          'display_name': displayName,
          'age': age,
          'latitude': latitude,
          'longitude': longitude,
          'looking_for': lookingFor,
        }),
      ),
      MyProfile.fromJson,
    );

/// Saves the edited profile (PUT {backendUrl}/profile/me). [lookingFor] is
/// the complete new selection: it replaces the saved one, and empty clears it.
Future<MyProfile> updateMyProfile({
  required String backendUrl,
  required String token,
  required String? displayName,
  required String? bio,
  required int age,
  required List<String> lookingFor,
  ProfileStats? stats,
  http.Client? client,
}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.put(
        _endpoint(backendUrl, '/profile/me'),
        headers: {..._authorization(token), 'Content-Type': 'application/json'},
        body: jsonEncode({
          'display_name': displayName,
          'bio': bio,
          'age': age,
          'looking_for': lookingFor,
          // only when edited; otherwise the backend keeps them
          ...?stats?.toJson(),
        }),
      ),
      MyProfile.fromJson,
    );

/// A question and its answer (null: skipped) on a tap sent while Tap had
/// questions; taps sent now have none.
class TapAnswer {
  const TapAnswer(
      {required this.question, required this.required, this.answer});

  factory TapAnswer.fromJson(Map<String, dynamic> json) => TapAnswer(
        question: json['question'] as String,
        required: json['required'] as bool? ?? false,
        answer: json['answer'] as String?,
      );

  final String question;
  final bool required;
  final String? answer;
}

/// A tap waiting in my Tap inbox.
class ReceivedTap {
  const ReceivedTap(
      {required this.id,
      required this.sender,
      required this.answers,
      required this.isRead,
      required this.receivedAt,
      this.count = 1});

  factory ReceivedTap.fromJson(Map<String, dynamic> json) => ReceivedTap(
        id: json['id'] as int,
        sender: Profile.nearby(json['sender'] as Map<String, dynamic>),
        answers: [
          for (final a in json['answers'] as List<dynamic>)
            TapAnswer.fromJson(a as Map<String, dynamic>),
        ],
        isRead: json['is_read'] as bool? ?? false,
        receivedAt: DateTime.parse(
                (json['last_tapped_at'] ?? json['created_at']) as String)
            .toLocal(),
        count: json['count'] as int? ?? 1,
      );

  final int id;
  final Profile sender;
  final List<TapAnswer> answers;
  final bool isRead;

  /// When they last tapped.
  final DateTime receivedAt;

  /// How many times they've tapped since I last answered (1: once).
  final int count;

  ReceivedTap read() => ReceivedTap(
      id: id,
      sender: sender,
      answers: answers,
      isRead: true,
      receivedAt: receivedAt,
      count: count);
}

/// After responding to a tap: the direct conversation and my message.
class TapResponse {
  const TapResponse({required this.conversationId, required this.message});

  factory TapResponse.fromJson(Map<String, dynamic> json) => TapResponse(
        conversationId: json['conversation_id'] as int,
        message: ChatMessage.fromJson(json['message'] as Map<String, dynamic>),
      );

  final int conversationId;
  final ChatMessage message;
}

Uri _taps(String backendUrl, [String path = '']) =>
    _endpoint(backendUrl, '/taps$path');

/// GET .../taps: the taps waiting for me, newest first.
Future<List<ReceivedTap>> fetchTapInbox(
        {required String backendUrl,
        required String token,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) =>
          httpClient.get(_taps(backendUrl), headers: _authorization(token)),
      (data) => [
        for (final t in data['taps'] as List<dynamic>)
          ReceivedTap.fromJson(t as Map<String, dynamic>),
      ],
    );

/// Someone who viewed my profile in the last 24 hours: how many times, and
/// when last.
class ProfileViewer {
  const ProfileViewer(
      {required this.person, required this.visits, required this.lastViewedAt});

  factory ProfileViewer.fromJson(Map<String, dynamic> json) => ProfileViewer(
        person: Profile.nearby(json['user'] as Map<String, dynamic>),
        visits: json['visits'] as int,
        lastViewedAt:
            DateTime.parse(json['last_viewed_at'] as String).toLocal(),
      );

  final Profile person;
  final int visits;
  final DateTime lastViewedAt;
}

/// A page of my profile viewers, latest visit first.
class ViewerPage {
  const ViewerPage({required this.viewers, required this.nextOffset});

  final List<ProfileViewer> viewers;

  /// Where the next page starts (null: this was the last).
  final int? nextOffset;
}

Uri _profileViews(String backendUrl) => _endpoint(backendUrl, '/profile-views');

/// POST .../profile-views: I opened their profile ([visitId]: this opening,
/// so sending it again counts once). The backend decides if it counts.
Future<void> recordProfileView(
        {required String backendUrl,
        required String token,
        required int userId,
        required String visitId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(_profileViews(backendUrl),
          headers: _json(token),
          body: jsonEncode({'user_id': userId, 'visit_id': visitId})),
      (_) {},
    );

/// GET .../profile-views/new-count: how many people viewed my profile
/// since I last opened Viewers.
Future<int> fetchNewProfileViewerCount(
        {required String backendUrl,
        required String token,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(
          _endpoint(backendUrl, '/profile-views/new-count'),
          headers: _authorization(token)),
      (data) => data['count'] as int,
    );

/// POST .../profile-views/seen: I opened Viewers (its badge clears).
Future<void> markProfileViewersSeen(
        {required String backendUrl,
        required String token,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _endpoint(backendUrl, '/profile-views/seen'),
          headers: _authorization(token)),
      (_) {},
    );

/// GET .../profile-views: who viewed my profile (only ever mine).
Future<ViewerPage> fetchProfileViewers(
        {required String backendUrl,
        required String token,
        int offset = 0,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(
          _profileViews(backendUrl)
              .replace(queryParameters: {'offset': '$offset'}),
          headers: _authorization(token)),
      (data) => ViewerPage(
        viewers: [
          for (final v in data['viewers'] as List<dynamic>)
            ProfileViewer.fromJson(v as Map<String, dynamic>),
        ],
        nextOffset: data['next_offset'] as int?,
      ),
    );

/// POST .../taps: tap them (it goes to their Taps inbox; no chat starts).
Future<void> sendTap(
        {required String backendUrl,
        required String token,
        required int recipientId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(_taps(backendUrl),
          headers: _json(token),
          body: jsonEncode({'recipient_id': recipientId})),
      (_) {},
    );

/// POST .../taps/{id}/read: I opened it.
Future<void> markTapRead(
        {required String backendUrl,
        required String token,
        required int tapId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(_taps(backendUrl, '/$tapId/read'),
          headers: _authorization(token)),
      (_) {},
    );

/// POST .../taps/{id}/respond: my response starts our direct conversation.
Future<TapResponse> respondToTap(
        {required String backendUrl,
        required String token,
        required int tapId,
        required String body,
        required String clientId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(_taps(backendUrl, '/$tapId/respond'),
          headers: _json(token),
          body: jsonEncode({'body': body, 'client_id': clientId})),
      TapResponse.fromJson,
    );

/// The one sexual position my profile shows; null: do not show
/// (PUT {backendUrl}/profile/me/position). Returns it as stored.
Future<String?> updateMyPosition({
  required String backendUrl,
  required String token,
  required String? sexualPosition,
  http.Client? client,
}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.put(
        _endpoint(backendUrl, '/profile/me/position'),
        headers: {..._authorization(token), 'Content-Type': 'application/json'},
        body: jsonEncode({'sexual_position': sexualPosition}),
      ),
      (data) => data['sexual_position'] as String?,
    );

/// Saves the privacy settings that are given; null leaves one unchanged
/// (PATCH {backendUrl}/profile/me/privacy). Returns both as stored.
Future<PrivacySettings> updateMyPrivacy({
  required String backendUrl,
  required String token,
  bool? showOnline,
  bool? showDistance,
  bool? showOnMap,
  bool? notifyTaps,
  bool? notifyMessages,
  bool? notifyStoryReplies,
  http.Client? client,
}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.patch(
        _endpoint(backendUrl, '/profile/me/privacy'),
        headers: {..._authorization(token), 'Content-Type': 'application/json'},
        body: jsonEncode({
          if (showOnline != null) 'show_online': showOnline,
          if (showDistance != null) 'show_distance': showDistance,
          if (showOnMap != null) 'show_on_map': showOnMap,
          if (notifyTaps != null) 'notify_taps': notifyTaps,
          if (notifyMessages != null) 'notify_messages': notifyMessages,
          if (notifyStoryReplies != null)
            'notify_story_replies': notifyStoryReplies,
        }),
      ),
      PrivacySettings.fromJson,
    );

/// POST .../devices: this device gets my push notifications ([platform]:
/// 'android', 'ios' or 'web').
Future<void> registerPushDevice(
        {required String backendUrl,
        required String token,
        required String pushToken,
        required String platform,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(_endpoint(backendUrl, '/devices'),
          headers: {
            ..._authorization(token),
            'Content-Type': 'application/json'
          },
          body: jsonEncode({'token': pushToken, 'platform': platform})),
      (_) {},
    );

/// POST .../devices/forget: signing out here; no more notifications.
Future<void> forgetPushDevice(
        {required String backendUrl,
        required String token,
        required String pushToken,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(_endpoint(backendUrl, '/devices/forget'),
          headers: {
            ..._authorization(token),
            'Content-Type': 'application/json'
          },
          body: jsonEncode({'token': pushToken})),
      (_) {},
    );

/// My profile photos and the limits for adding more.
class ProfilePhotoList {
  const ProfilePhotoList(
      {required this.photos,
      required this.maxPhotos,
      required this.maxUploadBytes});

  factory ProfilePhotoList.fromJson(Map<String, dynamic> json) =>
      ProfilePhotoList(
        photos: [
          for (final photo in json['photos'] as List<dynamic>)
            ProfilePhoto.fromJson(photo as Map<String, dynamic>),
        ],
        maxPhotos: json['max_photos'] as int,
        maxUploadBytes: json['max_upload_bytes'] as int,
      );

  final List<ProfilePhoto> photos;
  final int maxPhotos;
  final int maxUploadBytes;
}

/// The part of a photo to keep, as fractions 0-1 of its width and height.
class PhotoCrop {
  const PhotoCrop(
      {required this.x,
      required this.y,
      required this.width,
      required this.height});

  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, double> toJson() =>
      {'x': x, 'y': y, 'width': width, 'height': height};
}

Uri _photos(String backendUrl, [String path = '']) =>
    _endpoint(backendUrl, '/profile/photos$path');

/// GET {backendUrl}/profile/photos
Future<ProfilePhotoList> fetchMyPhotos({
  required String backendUrl,
  required String token,
  http.Client? client,
}) =>
    _sendAuthorized(
      client,
      (httpClient) =>
          httpClient.get(_photos(backendUrl), headers: _authorization(token)),
      ProfilePhotoList.fromJson,
    );

/// Uploads a photo with the confirmed crop (POST {backendUrl}/profile/photos).
/// The backend checks, crops, compresses and stores it.
Future<ProfilePhoto> uploadMyPhoto({
  required String backendUrl,
  required String token,
  required List<int> bytes,
  required String filename,
  required PhotoCrop crop,
  http.Client? client,
}) =>
    _sendAuthorized(
      client,
      (httpClient) async {
        final request = http.MultipartRequest('POST', _photos(backendUrl))
          ..headers.addAll(_authorization(token))
          ..fields.addAll({
            'crop_x': '${crop.x}',
            'crop_y': '${crop.y}',
            'crop_width': '${crop.width}',
            'crop_height': '${crop.height}',
          })
          ..files.add(
              http.MultipartFile.fromBytes('file', bytes, filename: filename));
        return http.Response.fromStream(await httpClient.send(request));
      },
      ProfilePhoto.fromJson,
    );

/// PATCH {backendUrl}/profile/photos/{id}/default - returns the new list.
Future<ProfilePhotoList> setMyDefaultPhoto({
  required String backendUrl,
  required String token,
  required int photoId,
  http.Client? client,
}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.patch(_photos(backendUrl, '/$photoId/default'),
          headers: _authorization(token)),
      ProfilePhotoList.fromJson,
    );

/// PUT {backendUrl}/profile/photos/order - all my photo ids in the new
/// order (the first becomes main); returns the new list.
Future<ProfilePhotoList> reorderMyPhotos({
  required String backendUrl,
  required String token,
  required List<int> photoIds,
  http.Client? client,
}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.put(
        _photos(backendUrl, '/order'),
        headers: {..._authorization(token), 'Content-Type': 'application/json'},
        body: jsonEncode({'photo_ids': photoIds}),
      ),
      ProfilePhotoList.fromJson,
    );

/// Crops a saved photo further (PUT .../{id}/crop).
Future<ProfilePhoto> recropMyPhoto({
  required String backendUrl,
  required String token,
  required int photoId,
  required PhotoCrop crop,
  http.Client? client,
}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.put(
        _photos(backendUrl, '/$photoId/crop'),
        headers: {..._authorization(token), 'Content-Type': 'application/json'},
        body: jsonEncode(crop.toJson()),
      ),
      ProfilePhoto.fromJson,
    );

/// DELETE {backendUrl}/profile/photos/{id} - returns the new list.
Future<ProfilePhotoList> removeMyPhoto({
  required String backendUrl,
  required String token,
  required int photoId,
  http.Client? client,
}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.delete(_photos(backendUrl, '/$photoId'),
          headers: _authorization(token)),
      ProfilePhotoList.fromJson,
    );

/// One of my albums as the backend returns it.
class StoredAlbum {
  const StoredAlbum(
      {required this.id, required this.name, required this.items});

  factory StoredAlbum.fromJson(Map<String, dynamic> json) => StoredAlbum(
        id: json['id'] as int,
        name: json['name'] as String,
        items: [
          for (final item in json['items'] as List<dynamic>)
            StoredAlbumItem.fromJson(item as Map<String, dynamic>),
        ],
      );

  final int id;
  final String name;
  final List<StoredAlbumItem> items;
}

/// My albums and the limits for them.
class AlbumList {
  const AlbumList({
    required this.albums,
    required this.maxAlbums,
    required this.maxItems,
    required this.maxPhotoBytes,
    required this.maxVideoBytes,
    required this.maxVideoSeconds,
    this.maxNameLength,
  });

  factory AlbumList.fromJson(Map<String, dynamic> json) => AlbumList(
        albums: [
          for (final album in json['albums'] as List<dynamic>)
            StoredAlbum.fromJson(album as Map<String, dynamic>),
        ],
        maxAlbums: json['max_albums'] as int,
        maxItems: json['max_items'] as int,
        maxPhotoBytes: json['max_photo_bytes'] as int,
        maxVideoBytes: json['max_video_bytes'] as int,
        maxVideoSeconds: json['max_video_seconds'] as int,
        maxNameLength: json['name_max_length'] as int?,
      );

  final List<StoredAlbum> albums;
  final int maxAlbums;

  /// Photos and videos together, per album.
  final int maxItems;
  final int maxPhotoBytes;
  final int maxVideoBytes;
  final int maxVideoSeconds;

  /// The longest album name (null: the backend doesn't say).
  final int? maxNameLength;
}

Uri _albums(String backendUrl, [String path = '']) =>
    _endpoint(backendUrl, '/albums$path');

/// GET {backendUrl}/albums
Future<AlbumList> fetchMyAlbums(
        {required String backendUrl,
        required String token,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) =>
          httpClient.get(_albums(backendUrl), headers: _authorization(token)),
      AlbumList.fromJson,
    );

/// POST {backendUrl}/albums
Future<StoredAlbum> createMyAlbum(
        {required String backendUrl,
        required String token,
        required String name,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(_albums(backendUrl),
          headers: {
            ..._authorization(token),
            'Content-Type': 'application/json'
          },
          body: jsonEncode({'name': name})),
      StoredAlbum.fromJson,
    );

/// PATCH {backendUrl}/albums/{id}
Future<StoredAlbum> renameMyAlbum(
        {required String backendUrl,
        required String token,
        required int albumId,
        required String name,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.patch(_albums(backendUrl, '/$albumId'),
          headers: {
            ..._authorization(token),
            'Content-Type': 'application/json'
          },
          body: jsonEncode({'name': name})),
      StoredAlbum.fromJson,
    );

/// DELETE {backendUrl}/albums/{id} - returns the remaining albums.
Future<AlbumList> deleteMyAlbum(
        {required String backendUrl,
        required String token,
        required int albumId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.delete(_albums(backendUrl, '/$albumId'),
          headers: _authorization(token)),
      AlbumList.fromJson,
    );

/// Adds a photo (with its confirmed crop) or a video to an album
/// (POST {backendUrl}/albums/{id}/media). The backend processes and stores it.
Future<StoredAlbumItem> addToMyAlbum({
  required String backendUrl,
  required String token,
  required int albumId,
  required List<int> bytes,
  required String filename,
  PhotoCrop? crop,
  http.Client? client,
}) =>
    _sendAuthorized(
      client,
      (httpClient) async {
        final request = http.MultipartRequest(
            'POST', _albums(backendUrl, '/$albumId/media'))
          ..headers.addAll(_authorization(token))
          ..files.add(
              http.MultipartFile.fromBytes('file', bytes, filename: filename));
        if (crop != null) {
          request.fields.addAll({
            'crop_x': '${crop.x}',
            'crop_y': '${crop.y}',
            'crop_width': '${crop.width}',
            'crop_height': '${crop.height}',
          });
        }
        return http.Response.fromStream(await httpClient.send(request));
      },
      StoredAlbumItem.fromJson,
    );

/// Crops an album photo further (PUT .../albums/{id}/media/{itemId}/crop);
/// the crop is a new item (new id).
Future<StoredAlbumItem> recropInMyAlbum(
        {required String backendUrl,
        required String token,
        required int albumId,
        required int itemId,
        required PhotoCrop crop,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.put(
          _albums(backendUrl, '/$albumId/media/$itemId/crop'),
          headers: {
            ..._authorization(token),
            'Content-Type': 'application/json'
          },
          body: jsonEncode(crop.toJson())),
      StoredAlbumItem.fromJson,
    );

/// PUT .../albums/{id}/media/order - all the album's item ids in the new
/// order; returns the album.
Future<StoredAlbum> reorderMyAlbum(
        {required String backendUrl,
        required String token,
        required int albumId,
        required List<int> itemIds,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.put(
          _albums(backendUrl, '/$albumId/media/order'),
          headers: {
            ..._authorization(token),
            'Content-Type': 'application/json'
          },
          body: jsonEncode({'media_ids': itemIds})),
      StoredAlbum.fromJson,
    );

/// DELETE .../albums/{id}/media/{itemId} - returns the album.
Future<StoredAlbum> removeFromMyAlbum(
        {required String backendUrl,
        required String token,
        required int albumId,
        required int itemId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.delete(
          _albums(backendUrl, '/$albumId/media/$itemId'),
          headers: _authorization(token)),
      StoredAlbum.fromJson,
    );

/// A one-time ticket for opening the presence WebSocket
/// (POST {backendUrl}/presence/ticket); the session token never goes in the
/// socket's URL.
Future<String> fetchWsTicket(
        {required String backendUrl,
        required String token,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(_endpoint(backendUrl, '/presence/ticket'),
          headers: _authorization(token)),
      (data) => data['ticket'] as String,
    );

/// The presence WebSocket's address for a ticket ({backendUrl}/ws, as ws/wss).
Uri presenceSocketUrl(String backendUrl, String ticket) {
  final http = _endpoint(backendUrl, '/ws');
  return http.replace(
      scheme: http.scheme == 'https' ? 'wss' : 'ws',
      queryParameters: {'ticket': ticket});
}

/// What a chat message is.
enum ChatMessageType {
  text,
  image,
  video,
  albumTrade,

  /// The album chosen in return for an [albumTrade], as its own message (at
  /// the bottom, when it was chosen); [ChatMessage.trade] is the trade.
  albumTradeReturn,
  location,
  liveLocation,

  /// The anonymous sender showed who they are; [ChatMessage.body] is the
  /// anonymous name they had.
  reveal,

  /// The recipient of an anonymous chat asked its sender to show who they are.
  revealRequest,

  /// The tap this direct conversation started from (its questions and
  /// answers, in [ChatMessage.tapAnswers]).
  tap,

  /// A GIF or sticker from GIPHY ([ChatMessage.gif]).
  gif,

  /// A reply or reaction to a story ([ChatMessage.body] is what was said).
  storyReply,

  /// Its sender is interested in my album (they said so after viewing it
  /// in a trade): "❤️ Sam is interested in your album!".
  albumInterest;

  static ChatMessageType parse(String? value) => switch (value) {
        'gif' => gif,
        'story_reply' => storyReply,
        'tap' => tap,
        'reveal' => reveal,
        'reveal_request' => revealRequest,
        'image' => image,
        'video' => video,
        'album_trade' => albumTrade,
        'album_trade_return' => albumTradeReturn,
        'album_interest' => albumInterest,
        'location' => location,
        'live_location' => liveLocation,
        _ => text,
      };
}

/// A direct message as the backend stores it, or my not-yet-confirmed copy
/// ([id] null while sending; [failed] when the send didn't go through).
/// Photos and videos have an [attachment], album trades a [trade].
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.fromMe,
    required this.body,
    required this.sentAt,
    this.clientId,
    this.failed = false,
    this.read = false,
    this.type = ChatMessageType.text,
    this.attachment,
    this.trade,
    this.upload,
    this.error,
    this.location,
    this.liveLocation,
    this.reactions = const [],
    this.replyTo,
    this.revealedAvatar,
    this.revealedMutual = false,
    this.tapAnswers = const [],
    this.gif,
    this.storyId,
    this.storyAvailable = false,
    this.storyThumbnailUrl,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as int,
        conversationId: json['conversation_id'] as int,
        fromMe: json['from_me'] as bool,
        body: json['body'] as String,
        sentAt: DateTime.parse(json['created_at'] as String).toLocal(),
        clientId: json['client_id'] as String?,
        read: json['is_read'] as bool? ?? false,
        type: ChatMessageType.parse(json['type'] as String?),
        attachment: json['attachment'] == null
            ? null
            : ChatAttachment.fromJson(
                json['attachment'] as Map<String, dynamic>),
        trade: json['trade'] == null
            ? null
            : AlbumTrade.fromJson(json['trade'] as Map<String, dynamic>),
        location: json['location'] == null
            ? null
            : LocationShare.fromJson(json['location'] as Map<String, dynamic>),
        liveLocation: json['live_location'] == null
            ? null
            : LiveLocationInfo.fromJson(
                json['live_location'] as Map<String, dynamic>),
        reactions: [
          for (final r in json['reactions'] as List? ?? const [])
            MessageReaction.fromJson(r as Map<String, dynamic>),
        ],
        replyTo: json['reply_to'] == null
            ? null
            : ReplyPreview.fromJson(json['reply_to'] as Map<String, dynamic>),
        revealedAvatar: (json['revealed_as']
            as Map<String, dynamic>?)?['avatar'] as String?,
        revealedMutual: (json['revealed_as']
                as Map<String, dynamic>?)?['mutual'] as bool? ??
            false,
        tapAnswers: [
          for (final a in json['tap'] as List<dynamic>? ?? const [])
            TapAnswer.fromJson(a as Map<String, dynamic>),
        ],
        gif: json['gif'] == null
            ? null
            : ChatGif.fromJson(json['gif'] as Map<String, dynamic>),
        storyId:
            (json['story_reply'] as Map<String, dynamic>?)?['story_id'] as int?,
        storyAvailable: (json['story_reply']
                as Map<String, dynamic>?)?['available'] as bool? ??
            false,
        storyThumbnailUrl: (json['story_reply']
            as Map<String, dynamic>?)?['thumbnail_url'] as String?,
      );

  /// A story reply: the story it answered.
  final int? storyId;

  /// A story reply: whether that story is still up (until it expires or is
  /// deleted), and then its thumbnail (none on a live event: fetched after).
  final bool storyAvailable;
  final String? storyThumbnailUrl;

  final ChatMessageType type;

  /// A GIF or sticker message: what to show.
  final ChatGif? gif;

  /// A reveal: the animal the sender was shown as while anonymous.
  final String? revealedAvatar;

  /// A reveal where both showed their profiles (a mutual chat).
  final bool revealedMutual;

  /// A tap card: answers to questions, on taps sent while Tap had them.
  final List<TapAnswer> tapAnswers;
  final ChatAttachment? attachment;
  final AlbumTrade? trade;

  /// A shared location (its position is only ever relayed live).
  final LocationShare? location;

  /// A live location sharing request / session.
  final LiveLocationInfo? liveLocation;

  /// Emoji reactions, one per person (text, photos and videos only).
  final List<MessageReaction> reactions;

  /// The message this one replies to (what its quote shows).
  final ReplyPreview? replyTo;

  /// Their text, photos, videos and GIFs take my reactions (not trades or
  /// locations, and never my own messages), once they're sent.
  bool get canReact =>
      id != null &&
      !fromMe &&
      (type == ChatMessageType.text ||
          type == ChatMessageType.image ||
          type == ChatMessageType.video ||
          type == ChatMessageType.gif);

  /// My reaction, if I reacted.
  String? get myReaction =>
      reactions.where((r) => r.fromMe).map((r) => r.emoji).firstOrNull;

  /// My photo or video still being sent (only on this device).
  final LocalUpload? upload;

  /// Why my send failed, when the server said (e.g. a video too long).
  final String? error;

  /// The server's id; null until the send is confirmed.
  final int? id;
  final int conversationId;
  final bool fromMe;
  final String body;
  final DateTime sentAt;

  /// Made by this app for my messages; reused when retrying.
  final String? clientId;
  final bool failed;

  /// The recipient has read it (shown as "Read" on my messages).
  final bool read;

  bool get pending => id == null;

  ChatMessage copyWith(
          {bool? failed,
          bool? read,
          LocalUpload? upload,
          String? error,
          bool clearError = false,
          List<MessageReaction>? reactions}) =>
      ChatMessage(
          id: id,
          conversationId: conversationId,
          fromMe: fromMe,
          body: body,
          sentAt: sentAt,
          clientId: clientId,
          failed: failed ?? this.failed,
          read: read ?? this.read,
          type: type,
          attachment: attachment,
          trade: trade,
          location: location,
          liveLocation: liveLocation,
          revealedAvatar: revealedAvatar,
          revealedMutual: revealedMutual,
          tapAnswers: tapAnswers,
          gif: gif,
          storyId: storyId,
          storyAvailable: storyAvailable,
          storyThumbnailUrl: storyThumbnailUrl,
          reactions: reactions ?? this.reactions,
          replyTo: replyTo,
          upload: upload ?? this.upload,
          error: clearError ? null : error ?? this.error);

  /// A short line for the chat list.
  String get preview => switch (type) {
        ChatMessageType.text => body,
        ChatMessageType.image => '📷 Photo',
        ChatMessageType.video => '🎥 Video',
        ChatMessageType.albumTrade => '🔁 Album trade',
        ChatMessageType.albumTradeReturn => '🔁 Traded an album',
        ChatMessageType.location => '📍 Location',
        ChatMessageType.liveLocation => '📍 Live location',
        ChatMessageType.reveal =>
          fromMe ? '🎉 You revealed yourself' : '🎉 $body revealed themselves',
        ChatMessageType.revealRequest =>
          fromMe ? '👀 You asked who they are' : '👀 Curious who you are',
        ChatMessageType.tap =>
          fromMe ? '👋 You tapped them' : '👋 They tapped you',
        ChatMessageType.gif => gif?.isSticker == true ? '✨ Sticker' : '🎞️ GIF',
        ChatMessageType.storyReply => '↩ Story reply: $body',
        ChatMessageType.albumInterest => fromMe
            ? '❤️ You’re interested in their album'
            : '❤️ Interested in your album',
      };
}

/// A GIF or sticker from GIPHY, as GIF search returns it and a GIF message
/// stores it. Its images load from GIPHY's media servers.
class ChatGif {
  const ChatGif({
    required this.id,
    required this.isSticker,
    required this.title,
    required this.url,
    required this.previewUrl,
    required this.width,
    required this.height,
  });

  factory ChatGif.fromJson(Map<String, dynamic> json) => ChatGif(
        id: json['id'] as String,
        isSticker: json['kind'] == 'sticker',
        title: json['title'] as String? ?? '',
        url: json['url'] as String,
        previewUrl: json['preview_url'] as String? ?? json['url'] as String,
        width: json['width'] as int,
        height: json['height'] as int,
      );

  final String id;

  /// A sticker (transparent, shown without a bubble) rather than a GIF.
  final bool isSticker;
  final String title;

  /// The animation shown in the chat (200px wide).
  final String url;

  /// A lighter one for the picker.
  final String previewUrl;
  final int width;
  final int height;
}

/// One page of GIF search or trending results.
class GifPage {
  const GifPage({required this.gifs, this.nextOffset});

  factory GifPage.fromJson(Map<String, dynamic> json) => GifPage(
        gifs: [
          for (final g in json['gifs'] as List<dynamic>)
            ChatGif.fromJson(g as Map<String, dynamic>),
        ],
        nextOffset: json['next_offset'] as int?,
      );

  final List<ChatGif> gifs;

  /// Where the next page starts (null: no more).
  final int? nextOffset;
}

/// What a reply's quote shows of the message it replies to: whose it is,
/// and its text (other kinds show what they are).
class ReplyPreview {
  const ReplyPreview(
      {required this.id,
      required this.fromMe,
      required this.type,
      this.body = ''});

  factory ReplyPreview.fromJson(Map<String, dynamic> json) => ReplyPreview(
        id: json['id'] as int,
        fromMe: json['from_me'] as bool? ?? false,
        type: ChatMessageType.parse(json['type'] as String?),
        body: json['body'] as String? ?? '',
      );

  /// The quote of [message] (one I'm replying to now).
  factory ReplyPreview.of(ChatMessage message) => ReplyPreview(
      id: message.id!,
      fromMe: message.fromMe,
      type: message.type,
      body: switch (message.type) {
        ChatMessageType.text => message.body,
        ChatMessageType.albumTrade => message.trade?.offeredAlbum?.name ?? '',
        _ => '',
      });

  final int id;
  final bool fromMe;
  final ChatMessageType type;
  final String body;

  /// One line for the quote.
  String get text => switch (type) {
        ChatMessageType.text => body,
        ChatMessageType.image => '📷 Photo',
        ChatMessageType.video => '🎥 Video',
        // which album (its name, when known)
        ChatMessageType.albumTrade =>
          body.isEmpty ? '🔁 Album trade' : '🔁 Album trade · “$body”',
        ChatMessageType.albumTradeReturn => '🔁 Traded an album',
        ChatMessageType.location => '📍 Location',
        ChatMessageType.liveLocation => '📍 Live location',
        ChatMessageType.reveal => '🎭 Profile shown',
        ChatMessageType.revealRequest => '👀 Asked who you are',
        ChatMessageType.tap => '👋 Tap',
        ChatMessageType.gif => '🎞️ GIF',
        ChatMessageType.storyReply => '↩ $body',
        ChatMessageType.albumInterest => '❤️ Interested in an album',
      };
}

/// One person's emoji on a message.
class MessageReaction {
  const MessageReaction({required this.emoji, required this.fromMe});

  factory MessageReaction.fromJson(Map<String, dynamic> json) =>
      MessageReaction(
          emoji: json['emoji'] as String,
          fromMe: json['from_me'] as bool? ?? false);

  final String emoji;
  final bool fromMe;
}

/// A location shared in a chat: once, or live until [endsAt] (or until the
/// sender stops it). Its position is never in the database: it arrives
/// live, and comes with the message while the backend keeps it (briefly,
/// in its cache) - see MessagingState.positionOf.
class LocationShare {
  const LocationShare(
      {required this.live, this.endsAt, this.stopped = false, this.position});

  factory LocationShare.fromJson(Map<String, dynamic> json) {
    final p = json['position'] as Map<String, dynamic>?;
    return LocationShare(
      live: json['live'] as bool? ?? false,
      endsAt: json['ends_at'] == null
          ? null
          : DateTime.parse(json['ends_at'] as String).toLocal(),
      stopped: json['stopped'] as bool? ?? false,
      position: p == null
          ? null
          : SharedPosition(
              latitude: (p['latitude'] as num).toDouble(),
              longitude: (p['longitude'] as num).toDouble(),
              accuracy: (p['accuracy'] as num?)?.toDouble(),
              at: p['at'] == null
                  ? DateTime.now()
                  : DateTime.parse(p['at'] as String).toLocal()),
    );
  }

  final bool live;
  final DateTime? endsAt;

  /// The sender stopped sharing it (no position any more).
  final bool stopped;

  /// The latest position the backend still had when the message came.
  final SharedPosition? position;

  /// Live sharing still running at [now].
  bool activeAt(DateTime now) =>
      live && !stopped && endsAt != null && now.isBefore(endsAt!);
}

/// A live location sharing request between the two people in a chat: asked
/// (pending), then shared both ways (active) until either stops it or goes
/// offline; or declined / cancelled. Never resumes once over.
class LiveLocationInfo {
  const LiveLocationInfo({
    required this.status,
    required this.requestedByMe,
    this.canAccept = false,
    this.canCancel = false,
    this.canStop = false,
    this.endReason,
    this.endedByMe,
    this.heartbeat = const Duration(seconds: 20),
  });

  factory LiveLocationInfo.fromJson(Map<String, dynamic> json) =>
      LiveLocationInfo(
        status: json['status'] as String,
        requestedByMe: json['requested_by_me'] as bool? ?? false,
        canAccept: json['can_accept'] as bool? ?? false,
        canCancel: json['can_cancel'] as bool? ?? false,
        canStop: json['can_stop'] as bool? ?? false,
        endReason: json['end_reason'] as String?,
        endedByMe: json['ended_by_me'] as bool?,
        heartbeat: Duration(seconds: json['heartbeat_seconds'] as int? ?? 20),
      );

  /// pending, active, declined, cancelled or ended.
  final String status;
  final bool requestedByMe;
  final bool canAccept;
  final bool canCancel;
  final bool canStop;

  /// Why it ended: stopped, offline or permission.
  final String? endReason;
  final bool? endedByMe;

  /// How often the app says it's still there while sharing.
  final Duration heartbeat;

  bool get pending => status == 'pending';
  bool get active => status == 'active';
}

/// Both people's latest positions in a live session (null: not known yet).
class LivePositions {
  const LivePositions({this.me, this.them});

  final SharedPosition? me;
  final SharedPosition? them;

  LivePositions copyWith({SharedPosition? me, SharedPosition? them}) =>
      LivePositions(me: me ?? this.me, them: them ?? this.them);
}

/// The latest position of a shared location, as it arrived (in memory only).
class SharedPosition {
  const SharedPosition(
      {required this.latitude,
      required this.longitude,
      required this.at,
      this.accuracy});

  final double latitude;
  final double longitude;
  final double? accuracy;

  /// When it arrived here.
  final DateTime at;
}

/// A photo or video in a chat. The chat shows only its small blurred
/// [previewUrl]; the media itself comes from [openChatMedia]. Its countdown
/// starts when the recipient first opens it ([expiresAt], from the server).
class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.isVideo,
    required this.width,
    required this.height,
    this.durationMs,
    this.previewUrl,
    this.expiresAt,
    this.expired = false,
  });

  factory ChatAttachment.fromJson(Map<String, dynamic> json) => ChatAttachment(
        id: json['id'] as int,
        isVideo: json['media_type'] == 'video',
        width: json['width'] as int,
        height: json['height'] as int,
        durationMs: json['duration_ms'] as int?,
        previewUrl: json['preview_url'] as String?,
        expiresAt: json['expires_at'] == null
            ? null
            : DateTime.parse(json['expires_at'] as String).toLocal(),
        expired: json['expired'] as bool? ?? false,
      );

  final int id;
  final bool isVideo;
  final int width;
  final int height;
  final int? durationMs;
  final String? previewUrl;

  /// Null until the recipient first opens it.
  final DateTime? expiresAt;
  final bool expired;

  /// Expired by now (the server's deadline, even before it says so).
  bool expiredAt(DateTime now) =>
      expired || (expiresAt != null && !now.isBefore(expiresAt!));
}

/// My photo or video while it's being sent: the picked file and how much of
/// it has gone up (0-1; 1 while the server processes it).
class LocalUpload {
  const LocalUpload(
      {required this.bytes,
      required this.filename,
      required this.isVideo,
      this.progress = 0});

  final List<int> bytes;
  final String filename;
  final bool isVideo;
  final double progress;

  LocalUpload withProgress(double progress) => LocalUpload(
      bytes: bytes, filename: filename, isVideo: isVideo, progress: progress);
}

/// An album in a trade card: its name, what it holds, its blurred previews
/// (the card's carousel), and how long the other person's access lasts
/// once the trade is completed (from their first open).
class TradeAlbum {
  const TradeAlbum({
    required this.id,
    required this.name,
    this.photoCount = 0,
    this.videoCount = 0,
    this.previews = const [],
    this.expiresAt,
    this.expired = false,
  });

  factory TradeAlbum.fromJson(Map<String, dynamic> json) => TradeAlbum(
        id: json['id'] as int,
        name: json['name'] as String,
        photoCount: json['photo_count'] as int? ?? 0,
        videoCount: json['video_count'] as int? ?? 0,
        previews: [
          for (final p in json['previews'] as List<dynamic>? ?? const [])
            TradePreview(
                url: (p as Map<String, dynamic>)['url'] as String,
                isVideo: p['is_video'] as bool? ?? false),
        ],
        expiresAt: json['expires_at'] == null
            ? null
            : DateTime.parse(json['expires_at'] as String).toLocal(),
        expired: json['expired'] as bool? ?? false,
      );

  final int id;
  final String name;
  final int photoCount;
  final int videoCount;
  final List<TradePreview> previews;

  /// Null until the other person first opens it.
  final DateTime? expiresAt;
  final bool expired;

  bool expiredAt(DateTime now) =>
      expired || (expiresAt != null && !now.isBefore(expiresAt!));

  /// "3 photos · 1 video".
  String get contents {
    String count(int n, String one) => '$n ${n == 1 ? one : '${one}s'}';
    return [
      if (photoCount > 0) count(photoCount, 'photo'),
      if (videoCount > 0) count(videoCount, 'video'),
    ].join(' · ').ifEmpty('Empty album');
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// A blurred copy of one item of a traded album.
class TradePreview {
  const TradePreview({required this.url, required this.isVideo});
  final String url;
  final bool isVideo;
}

/// The other person's album of a completed trade, opened: short-lived
/// links (never past [expiresAt]).
class TradedAlbumAccess {
  const TradedAlbumAccess({
    required this.name,
    required this.items,
    required this.view,
  });

  /// [backendUrl]: where the session's media is served from.
  factory TradedAlbumAccess.fromJson(
          Map<String, dynamic> json, String backendUrl) =>
      TradedAlbumAccess(
        name: (json['album'] as Map<String, dynamic>)['name'] as String,
        items: [
          for (final item in json['items'] as List<dynamic>)
            StoredAlbumItem.fromJson({
              ...item as Map<String, dynamic>,
              'url': _served(backendUrl, item['content_path'] as String),
              'thumbnail_url': item['poster_path'] == null
                  ? null
                  : _served(backendUrl, item['poster_path'] as String),
            }),
        ],
        view: MediaView.fromJson(json),
      );

  final String name;

  /// Served through [view] only while it's open.
  final List<StoredAlbumItem> items;
  final MediaView view;
}

/// A viewing session: the media is served only through it, it stays open
/// while the viewer sends heartbeats, and closing it ends access. The
/// recipient's countdown is paused while they view and starts when they
/// leave.
class MediaView {
  const MediaView(
      {required this.token,
      required this.heartbeat,
      required this.countdownPaused});

  factory MediaView.fromJson(Map<String, dynamic> json) => MediaView(
        token: json['view_token'] as String,
        heartbeat: Duration(seconds: json['heartbeat_seconds'] as int? ?? 20),
        countdownPaused: json['countdown_paused'] as bool? ?? false,
      );

  final String token;
  final Duration heartbeat;

  /// My viewing paused the countdown (it starts when I close the viewer).
  final bool countdownPaused;
}

/// A path the backend serves (relative to its API) as a full address.
String _served(String backendUrl, String path) =>
    _endpoint(backendUrl, path).toString();

enum TradeStatus { pending, completed, cancelled }

/// An album trade offered in a chat. Completing it only records both
/// choices; no album is shared or transferred.
class AlbumTrade {
  const AlbumTrade({
    required this.id,
    required this.status,
    required this.fromMe,
    this.offeredAlbum,
    this.returnedAlbum,
    this.canRespond = false,
    this.canCancel = false,
    this.completedAt,
    this.returnMessageId,
    this.myInterest,
  });

  factory AlbumTrade.fromJson(Map<String, dynamic> json) => AlbumTrade(
        id: json['id'] as int,
        status: switch (json['status']) {
          'completed' => TradeStatus.completed,
          'cancelled' => TradeStatus.cancelled,
          _ => TradeStatus.pending,
        },
        fromMe: json['from_me'] as bool,
        offeredAlbum: json['offered_album'] == null
            ? null
            : TradeAlbum.fromJson(
                json['offered_album'] as Map<String, dynamic>),
        returnedAlbum: json['returned_album'] == null
            ? null
            : TradeAlbum.fromJson(
                json['returned_album'] as Map<String, dynamic>),
        canRespond: json['can_respond'] as bool? ?? false,
        canCancel: json['can_cancel'] as bool? ?? false,
        completedAt: json['completed_at'] == null
            ? null
            : DateTime.parse(json['completed_at'] as String).toLocal(),
        returnMessageId: json['return_message_id'] as int?,
        myInterest: json['my_interest'] as String?,
      );

  /// The message the album chosen in return came as (null: not chosen yet,
  /// or a trade from before those messages - its album shows under the
  /// offer).
  final int? returnMessageId;

  final int id;
  final TradeStatus status;

  /// I offered it.
  final bool fromMe;
  final TradeAlbum? offeredAlbum;
  final TradeAlbum? returnedAlbum;

  /// I'm the one it was offered to and it's still pending.
  final bool canRespond;
  final bool canCancel;

  /// When the other album was chosen in return.
  final DateTime? completedAt;

  /// Mine only: after I closed their album, asked whether I'm interested
  /// ("pending"), or how I answered ("interested", "not_now"); null when
  /// not asked.
  final String? myInterest;

  /// Asked, and not answered yet.
  bool get interestAsked =>
      status == TradeStatus.completed && myInterest == 'pending';

  /// The album I get to open once it's completed (the other person's).
  TradeAlbum? get theirAlbum => fromMe ? returnedAlbum : offeredAlbum;

  /// The album I chose.
  TradeAlbum? get myAlbum => fromMe ? offeredAlbum : returnedAlbum;
}

/// Access to the actual photo or video of an attachment: short-lived links
/// (never past its expiry).
class MediaAccess {
  const MediaAccess({
    required this.url,
    required this.isVideo,
    required this.view,
    this.posterUrl,
  });

  /// [backendUrl]: where the session's media is served from.
  factory MediaAccess.fromJson(Map<String, dynamic> json, String backendUrl) =>
      MediaAccess(
        url: _served(backendUrl, json['content_path'] as String),
        isVideo: json['media_type'] == 'video',
        posterUrl: json['poster_path'] == null
            ? null
            : _served(backendUrl, json['poster_path'] as String),
        view: MediaView.fromJson(json),
      );

  /// Served only while [view] is open.
  final String url;
  final bool isVideo;
  final String? posterUrl;
  final MediaView view;
}

/// One of my conversations in the list.
class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.other,
    required this.lastMessage,
    required this.unreadCount,
    this.anonymous,
    this.reveal,
    this.canSend = true,
    this.unmatched = false,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as int;
    final other = json['other'] as Map<String, dynamic>;
    final anonymous = json['anonymous'] as Map<String, dynamic>?;
    return ConversationSummary(
      id: id,
      // someone anonymous to me has no id: shown by their anonymous name
      other: other['anonymous'] == true
          ? Profile.anonymous(id, other)
          : Profile.nearby(other),
      lastMessage: json['last_message'] == null
          ? null
          : ChatMessage.fromJson(json['last_message'] as Map<String, dynamic>),
      unreadCount: json['unread_count'] as int? ?? 0,
      anonymous: anonymous == null ? null : AnonymousInfo.fromJson(anonymous),
      reveal: json['reveal'] == null
          ? null
          : RevealRequest.fromJson(json['reveal'] as Map<String, dynamic>),
      canSend: json['can_send'] as bool? ?? true,
      unmatched: json['unmatched'] as bool? ?? false,
    );
  }

  final int id;

  /// The other person: a real user, or (when they're anonymous to me) only
  /// their anonymous name and avatar.
  final Profile other;
  final ChatMessage? lastMessage;
  final int unreadCount;

  /// An anonymous conversation (in the Anonymous tab); null for a direct one.
  final AnonymousInfo? anonymous;

  /// The request to see the anonymous sender's profile, if one was made.
  final RevealRequest? reveal;

  /// I can write here (an anonymous conversation can be closed to me).
  final bool canSend;

  /// One of us is on the other's Unmatched list (closed, history kept).
  final bool unmatched;

  ConversationSummary copyWith(
          {ChatMessage? lastMessage,
          int? unreadCount,
          RevealRequest? reveal,
          bool? canSend}) =>
      ConversationSummary(
          id: id,
          other: other,
          lastMessage: lastMessage ?? this.lastMessage,
          unreadCount: unreadCount ?? this.unreadCount,
          anonymous: anonymous,
          reveal: reveal ?? this.reveal,
          canSend: canSend ?? this.canSend,
          unmatched: unmatched);
}

/// Who is anonymous in an anonymous conversation, and as what.
class AnonymousInfo {
  const AnonymousInfo(
      {required this.iAmAnonymous,
      required this.name,
      required this.avatar,
      this.mutual = false,
      this.myName,
      this.myAvatar});

  factory AnonymousInfo.fromJson(Map<String, dynamic> json) => AnonymousInfo(
        iAmAnonymous: json['i_am_anonymous'] as bool? ?? false,
        name: json['name'] as String? ?? 'Anonymous',
        avatar: json['avatar'] as String? ?? 'fox',
        mutual: json['mutual'] as bool? ?? false,
        myName: json['my_name'] as String?,
        myAvatar: json['my_avatar'] as String?,
      );

  /// I write anonymously here (they don't know who I am); otherwise they do.
  final bool iAmAnonymous;

  /// The anonymous side's name and animal (in a mutual chat: the one who
  /// started it).
  final String name;
  final String avatar;

  /// Both anonymous to each other (a chat from Threads): either may ask to
  /// show both profiles, and nothing stops the chat meanwhile.
  final bool mutual;

  /// How they see me, when I'm anonymous to them.
  final String? myName;
  final String? myAvatar;

  /// My anonymous name here.
  String get shownAs => myName ?? name;

  /// They're anonymous to me (I only know them by their anonymous name).
  bool get theyAreAnonymous => mutual || !iAmAnonymous;

  /// Only I'm anonymous: a mask over their real picture.
  bool get onlyMeMasked => iAmAnonymous && !mutual;
}

enum RevealStatus { pending, accepted, declined, expired }

/// A request to see the anonymous sender's profile (in a mutual chat: to
/// show both, asked by either).
class RevealRequest {
  const RevealRequest(
      {required this.status, this.expiresAt, this.requestedByMe = false});

  factory RevealRequest.fromJson(Map<String, dynamic> json) => RevealRequest(
        status: RevealStatus.values.firstWhere((s) => s.name == json['status'],
            orElse: () => RevealStatus.pending),
        expiresAt: json['expires_at'] == null
            ? null
            : DateTime.parse(json['expires_at'] as String).toLocal(),
        requestedByMe: json['requested_by_me'] as bool? ?? false,
      );

  final RevealStatus status;

  /// I asked (otherwise they did).
  final bool requestedByMe;

  /// While pending: when it expires unanswered.
  final DateTime? expiresAt;
}

/// The anonymous sender as I (the recipient) may see them: nothing from
/// their real profile.
class AnonymousProfile {
  const AnonymousProfile({
    required this.conversationId,
    required this.name,
    required this.avatar,
    required this.online,
    this.distanceKm,
    this.blocked = false,
    this.reveal,
    this.canRequestReveal = false,
    this.unmatched = false,
    this.mutual = false,
  });

  factory AnonymousProfile.fromJson(Map<String, dynamic> json) =>
      AnonymousProfile(
        conversationId: json['conversation_id'] as int,
        name: json['name'] as String,
        avatar: json['avatar'] as String,
        online: const {'online', 'stale'}.contains(json['presence']),
        distanceKm: json['distance_km'] as int?,
        blocked: json['blocked'] != null,
        reveal: json['reveal'] == null
            ? null
            : RevealRequest.fromJson(json['reveal'] as Map<String, dynamic>),
        canRequestReveal: json['can_request_reveal'] as bool? ?? false,
        unmatched: json['unmatched'] as bool? ?? false,
        mutual: json['mutual'] as bool? ?? false,
      );

  final int conversationId;
  final String name;
  final String avatar;
  final bool online;

  /// Whole kilometres; null when they don't share it.
  final int? distanceKm;
  final bool blocked;
  final RevealRequest? reveal;
  final bool canRequestReveal;

  /// On my Unmatched Users list (I can only remove them from it).
  final bool unmatched;

  /// Both of us are anonymous (a chat from Threads).
  final bool mutual;
}

/// After answering a reveal request: accepted, the chat is now this direct
/// conversation.
class RevealAnswer {
  const RevealAnswer({required this.accepted, this.directConversationId});

  factory RevealAnswer.fromJson(Map<String, dynamic> json) => RevealAnswer(
        accepted: json['accepted'] as bool,
        directConversationId: json['direct_conversation_id'] as int?,
      );

  final bool accepted;
  final int? directConversationId;
}

Uri _anonymous(String backendUrl, [String path = '']) =>
    _endpoint(backendUrl, '/anonymous$path');

Map<String, String> _json(String token) =>
    {..._authorization(token), 'Content-Type': 'application/json'};

/// GET .../anonymous/conversations: my anonymous conversations (both ways).
/// GET .../anonymous/conversations: a page of my anonymous conversations.
Future<ConversationPage> fetchAnonymousConversations(
        {required String backendUrl,
        required String token,
        String? before,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(
          _page(_anonymous(backendUrl, '/conversations'), before),
          headers: _authorization(token)),
      ConversationPage.fromJson,
    );

/// POST .../anonymous/conversations/{id}/messages: text, or a GIF/sticker
/// ([gifId], from GIF search) instead.
Future<ChatMessage> sendAnonymousMessage(
        {required String backendUrl,
        required String token,
        required int conversationId,
        required String body,
        required String clientId,
        int? replyToId,
        String? gifId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _anonymous(backendUrl, '/conversations/$conversationId/messages'),
          headers: _json(token),
          body: jsonEncode({
            ..._textOrGif(body, gifId),
            'client_id': clientId,
            if (replyToId != null) 'reply_to_id': replyToId,
          })),
      ChatMessage.fromJson,
    );

/// What a send carries: the text, or the GIF picked instead of text.
Map<String, String> _textOrGif(String body, String? gifId) =>
    gifId != null ? {'gif_id': gifId} : {'body': body};

/// GET .../gifs/trending or .../gifs/search: GIFs (or [stickers]) for the
/// chat's GIF picker; trending when [query] is empty.
Future<GifPage> fetchGifs(
        {required String backendUrl,
        required String token,
        required bool stickers,
        String query = '',
        int offset = 0,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(
          _endpoint(
                  backendUrl, query.isEmpty ? '/gifs/trending' : '/gifs/search')
              .replace(queryParameters: {
            'kind': stickers ? 'sticker' : 'gif',
            if (query.isNotEmpty) 'q': query,
            'offset': '$offset',
          }),
          headers: _authorization(token)),
      GifPage.fromJson,
    );

/// GET .../anonymous/conversations/{id}/profile: the anonymous sender.
Future<AnonymousProfile> fetchAnonymousProfile(
        {required String backendUrl,
        required String token,
        required int conversationId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(
          _anonymous(backendUrl, '/conversations/$conversationId/profile'),
          headers: _authorization(token)),
      AnonymousProfile.fromJson,
    );

/// POST .../reveal-request: ask the anonymous sender to show their profile.
Future<AnonymousProfile> requestReveal(
        {required String backendUrl,
        required String token,
        required int conversationId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _anonymous(
              backendUrl, '/conversations/$conversationId/reveal-request'),
          headers: _authorization(token)),
      AnonymousProfile.fromJson,
    );

/// POST .../reveal-request/answer: accept (it becomes a direct chat) or
/// decline (they block me; I stay anonymous).
Future<RevealAnswer> answerReveal(
        {required String backendUrl,
        required String token,
        required int conversationId,
        required bool accept,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _anonymous(backendUrl,
              '/conversations/$conversationId/reveal-request/answer'),
          headers: _json(token),
          body: jsonEncode({'accept': accept})),
      RevealAnswer.fromJson,
    );

/// POST .../report: report the other member of an anonymous conversation.
Future<void> reportAnonymous(
        {required String backendUrl,
        required String token,
        required int conversationId,
        required String reason,
        String? details,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _anonymous(backendUrl, '/conversations/$conversationId/report'),
          headers: _json(token),
          body: jsonEncode({
            'reason': reason,
            if (details != null && details.trim().isNotEmpty)
              'details': details.trim(),
          })),
      (_) {},
    );

/// DELETE .../anonymous/conversations/{id}/block: unblock its anonymous
/// sender (whom I only know by this conversation).
Future<void> unblockAnonymous(
        {required String backendUrl,
        required String token,
        required int conversationId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.delete(
          _anonymous(backendUrl, '/conversations/$conversationId/block'),
          headers: _authorization(token)),
      (_) {},
    );

/// One entry of my Unmatched Users list: a person, or (someone I only know
/// anonymously) their anonymous name and animal.
class UnmatchedPerson {
  const UnmatchedPerson(
      {this.userId,
      required this.name,
      this.photoUrl,
      this.anonymousConversationId,
      this.anonymousAvatar,
      required this.unmatchedAt});

  factory UnmatchedPerson.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    final anonymous = json['anonymous'] as Map<String, dynamic>?;
    return UnmatchedPerson(
      userId: user?['id'] as int?,
      name: (user?['display_name'] as String?)?.trim() ??
          anonymous?['name'] as String? ??
          '',
      photoUrl: user?['photo_url'] as String?,
      anonymousConversationId: anonymous?['conversation_id'] as int?,
      anonymousAvatar: anonymous?['avatar'] as String?,
      unmatchedAt: DateTime.parse(json['unmatched_at'] as String).toLocal(),
    );
  }

  /// Null for someone I only know anonymously.
  final int? userId;
  final String name;
  final String? photoUrl;
  final int? anonymousConversationId;
  final String? anonymousAvatar;
  final DateTime unmatchedAt;

  bool get isAnonymous => userId == null;

  /// Tells entries apart (a user id, or the anonymous conversation).
  String get ref =>
      userId != null ? '$userId' : 'anon-$anonymousConversationId';
}

Uri _unmatches(String backendUrl, [String path = '']) =>
    _endpoint(backendUrl, '/unmatches$path');

/// GET .../unmatches: my Unmatched Users list.
Future<List<UnmatchedPerson>> fetchMyUnmatches(
        {required String backendUrl,
        required String token,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(_unmatches(backendUrl),
          headers: _authorization(token)),
      (data) => [
        for (final u in data['unmatched'] as List<dynamic>)
          UnmatchedPerson.fromJson(u as Map<String, dynamic>),
      ],
    );

/// POST .../unmatches: unmatch someone I know (their chats leave both lists).
Future<void> unmatchUser(
        {required String backendUrl,
        required String token,
        required int userId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(_unmatches(backendUrl),
          headers: _json(token), body: jsonEncode({'user_id': userId})),
      (_) {},
    );

/// DELETE .../unmatches/{id}: take them off my list.
Future<void> removeUnmatch(
        {required String backendUrl,
        required String token,
        required int userId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.delete(_unmatches(backendUrl, '/$userId'),
          headers: _authorization(token)),
      (_) {},
    );

/// GET .../unmatches/{id}/profile: their profile, from my list only.
Future<Profile> fetchUnmatchedProfile(
        {required String backendUrl,
        required String token,
        required int userId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(_unmatches(backendUrl, '/$userId/profile'),
          headers: _authorization(token)),
      Profile.nearby,
    );

/// POST / DELETE .../anonymous/conversations/{id}/unmatch: unmatch the other
/// member of an anonymous chat, or take them off my list again.
Future<void> setAnonymousUnmatch(
        {required String backendUrl,
        required String token,
        required int conversationId,
        required bool unmatched,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) {
        final uri =
            _anonymous(backendUrl, '/conversations/$conversationId/unmatch');
        final headers = _authorization(token);
        return unmatched
            ? httpClient.post(uri, headers: headers)
            : httpClient.delete(uri, headers: headers);
      },
      (_) {},
    );

/// PUT .../anonymous/settings: my Anonymous messaging setting.
Future<bool> setAnonymousMessaging(
        {required String backendUrl,
        required String token,
        required bool enabled,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.put(_anonymous(backendUrl, '/settings'),
          headers: _json(token), body: jsonEncode({'enabled': enabled})),
      (data) => data['anonymous_messaging_enabled'] as bool,
    );

/// A page of a conversation's messages, in chronological order.
class MessagePage {
  const MessagePage({required this.messages, required this.hasMore});

  factory MessagePage.fromJson(Map<String, dynamic> json) => MessagePage(
        messages: [
          for (final m in json['messages'] as List<dynamic>)
            ChatMessage.fromJson(m as Map<String, dynamic>),
        ],
        hasMore: json['has_more'] as bool,
      );

  final List<ChatMessage> messages;

  /// More in the direction asked for (older, or newer when catching up).
  final bool hasMore;
}

/// GET {backendUrl}/conversations
/// A page of the Chats (or Anonymous) list, newest activity first.
class ConversationPage {
  ConversationPage(
      {required this.conversations, int? unreadTotal, this.nextBefore})
      : unreadTotal = unreadTotal ??
            conversations.fold<int>(0, (sum, c) => sum + c.unreadCount);

  factory ConversationPage.fromJson(Map<String, dynamic> data) =>
      ConversationPage(
        conversations: [
          for (final c in data['conversations'] as List<dynamic>)
            ConversationSummary.fromJson(c as Map<String, dynamic>),
        ],
        unreadTotal: data['unread_total'] as int?,
        nextBefore: data['next_before'] as String?,
      );

  final List<ConversationSummary> conversations;

  /// Unread across all my conversations of this kind, not only this page.
  final int unreadTotal;

  /// Where the next page starts (null: this was the last).
  final String? nextBefore;
}

Uri _page(Uri url, String? before) =>
    before == null ? url : url.replace(queryParameters: {'before': before});

/// GET .../conversations: a page of my direct conversations ([before]: the
/// last page's [ConversationPage.nextBefore]).
Future<ConversationPage> fetchConversations(
        {required String backendUrl,
        required String token,
        String? before,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(
          _page(_endpoint(backendUrl, '/conversations'), before),
          headers: _authorization(token)),
      ConversationPage.fromJson,
    );

/// Where Message on a profile goes (POST .../conversations/start): our
/// direct conversation when we have one, otherwise my anonymous one with
/// them (started the first time). From Threads, our chat where both stay
/// anonymous.
class MessageTarget {
  const MessageTarget(
      {required this.conversationId, this.other, this.anonymous});

  factory MessageTarget.fromJson(Map<String, dynamic> json) {
    final conversation = json['conversation'] as Map<String, dynamic>;
    final summary = ConversationSummary.fromJson(conversation);
    return MessageTarget(
      conversationId: summary.id,
      other: summary.other,
      anonymous: json['anonymous'] == true ? summary : null,
    );
  }

  final int conversationId;

  /// Whom the chat is with (as the chat shows them: anonymous or not).
  final Profile? other;

  /// The anonymous conversation, when it's one (null: direct).
  final ConversationSummary? anonymous;
}

/// POST .../nearby/posts/{id}[/comments/{id}]/message: Message on the
/// anonymous profile of whoever wrote it, our chat where both of us stay
/// anonymous (or our direct one, once we've shown each other).
Future<MessageTarget> messageThreadsAuthor(
        {required String backendUrl,
        required String token,
        required int postId,
        int? commentId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _endpoint(
              backendUrl,
              commentId == null
                  ? '/nearby/posts/$postId/message'
                  : '/nearby/posts/$postId/comments/$commentId/message'),
          headers: _json(token)),
      MessageTarget.fromJson,
    );

Future<MessageTarget> startConversation(
        {required String backendUrl,
        required String token,
        required int userId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _endpoint(backendUrl, '/conversations/start'),
          headers: _json(token),
          body: jsonEncode({'user_id': userId})),
      MessageTarget.fromJson,
    );

/// GET .../conversations/{id}/messages: the newest page, older than [before],
/// or newer than [after].
Future<MessagePage> fetchMessages(
        {required String backendUrl,
        required String token,
        required int conversationId,
        int? before,
        int? after,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(
          _endpoint(backendUrl, '/conversations/$conversationId/messages')
              .replace(queryParameters: {
            if (before != null) 'before': '$before',
            if (after != null) 'after': '$after',
          }),
          headers: _authorization(token)),
      MessagePage.fromJson,
    );

/// POST {backendUrl}/messages: saved once per [clientId] (a retry returns
/// the stored message). Text, or a GIF/sticker ([gifId]) instead.
Future<ChatMessage> sendMessage(
        {required String backendUrl,
        required String token,
        required int recipientId,
        required String body,
        required String clientId,
        int? replyToId,
        String? gifId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(_endpoint(backendUrl, '/messages'),
          headers: {
            ..._authorization(token),
            'Content-Type': 'application/json'
          },
          body: jsonEncode({
            'recipient_id': recipientId,
            ..._textOrGif(body, gifId),
            'client_id': clientId,
            if (replyToId != null) 'reply_to_id': replyToId,
          })),
      ChatMessage.fromJson,
    );

/// POST .../conversations/{id}/read: my unread messages there are read.
Future<void> markConversationRead(
        {required String backendUrl,
        required String token,
        required int conversationId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _endpoint(backendUrl, '/conversations/$conversationId/read'),
          headers: _authorization(token)),
      (_) {},
    );

/// GET {backendUrl}/messages/{id}: one message with its media or trade
/// (live events only name it).
Future<ChatMessage> fetchMessage(
        {required String backendUrl,
        required String token,
        required int messageId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(
          _endpoint(backendUrl, '/messages/$messageId'),
          headers: _authorization(token)),
      ChatMessage.fromJson,
    );

/// POST {backendUrl}/messages/media: a photo or video, saved once per
/// [clientId]. [onProgress] gets the share of the file sent so far (0-1).
Future<ChatMessage> sendChatMedia({
  required String backendUrl,
  required String token,
  required int recipientId,
  required List<int> bytes,
  required String filename,
  required String clientId,
  int? replyToId,
  void Function(double sent)? onProgress,
  http.Client? client,
}) =>
    _sendAuthorized(
      client,
      (httpClient) async {
        final uri = _endpoint(backendUrl, '/messages/media');
        final multipart = http.MultipartRequest('POST', uri)
          ..headers.addAll(_authorization(token))
          ..fields.addAll({
            'recipient_id': '$recipientId',
            'client_id': clientId,
            if (replyToId != null) 'reply_to_id': '$replyToId',
          })
          ..files.add(
              http.MultipartFile.fromBytes('file', bytes, filename: filename));
        return _sendCountingProgress(httpClient, multipart, onProgress);
      },
      ChatMessage.fromJson,
    );

/// Sends [multipart] with its body going through a counter, for a progress
/// bar: [onProgress] gets the share sent so far (0-1).
Future<http.Response> _sendCountingProgress(
    http.Client httpClient,
    http.MultipartRequest multipart,
    void Function(double sent)? onProgress) async {
  final body = multipart.finalize();
  final total = multipart.contentLength;
  final request = http.StreamedRequest(multipart.method, multipart.url)
    ..headers.addAll(multipart.headers)
    ..contentLength = total;
  var sent = 0;
  body.listen((chunk) {
    sent += chunk.length;
    onProgress?.call(total == 0 ? 1 : sent / total);
    request.sink.add(chunk);
  }, onDone: request.sink.close, onError: request.sink.addError);
  return http.Response.fromStream(await httpClient.send(request));
}

/// A story (My Day): a short public video for 24 hours.
class Story {
  const Story({
    required this.id,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.width,
    required this.height,
    required this.duration,
    required this.postedAt,
    required this.expiresAt,
    this.seen = false,
    this.viewCount,
  });

  factory Story.fromJson(Map<String, dynamic> json) => Story(
        id: json['id'] as int,
        videoUrl: json['video_url'] as String,
        thumbnailUrl: json['thumbnail_url'] as String,
        width: json['width'] as int,
        height: json['height'] as int,
        duration: Duration(milliseconds: json['duration_ms'] as int),
        postedAt: DateTime.parse(json['created_at'] as String).toLocal(),
        expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
        seen: json['seen'] as bool? ?? false,
        viewCount: json['view_count'] as int?,
      );

  final int id;

  /// Temporary links (about an hour).
  final String videoUrl;
  final String thumbnailUrl;
  final int width;
  final int height;
  final Duration duration;
  final DateTime postedAt;
  final DateTime expiresAt;

  /// I've watched it (someone else's story).
  final bool seen;

  /// How many people watched it (only on my own; null on theirs).
  final int? viewCount;
}

/// Someone who watched my story.
class StoryViewer {
  const StoryViewer(
      {required this.userId,
      required this.name,
      required this.viewedAt,
      this.photoUrl,
      this.reaction});

  factory StoryViewer.fromJson(Map<String, dynamic> json) => StoryViewer(
        userId: json['id'] as int,
        name: json['display_name'] as String? ?? '',
        photoUrl: json['photo_url'] as String?,
        viewedAt: DateTime.parse(json['viewed_at'] as String).toLocal(),
        reaction: json['reaction'] as String?,
      );

  final int userId;
  final String name;
  final String? photoUrl;
  final DateTime viewedAt;

  /// Their reaction (❤️, 😍 or 👍), if they sent one.
  final String? reaction;
}

Uri _stories(String backendUrl, [String path = '']) =>
    _endpoint(backendUrl, '/stories$path');

List<Story> _storyList(Map<String, dynamic> data) => [
      for (final s in data['stories'] as List<dynamic>)
        Story.fromJson(s as Map<String, dynamic>),
    ];

/// GET .../stories/users/{id}: their stories, oldest first (mine when it's
/// me).
Future<List<Story>> fetchStoriesOf(
        {required String backendUrl,
        required String token,
        required int userId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(_stories(backendUrl, '/users/$userId'),
          headers: _authorization(token)),
      _storyList,
    );

/// GET .../stories/mine: my stories, with how many watched each.
Future<List<Story>> fetchMyStories(
        {required String backendUrl,
        required String token,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(_stories(backendUrl, '/mine'),
          headers: _authorization(token)),
      _storyList,
    );

/// POST .../stories: a video; the backend keeps [length] (at most
/// [StoryService.maxLength]) from [start], the user's trim. [onProgress] gets
/// the share of the file sent so far (0-1).
Future<Story> postStory({
  required String backendUrl,
  required String token,
  required List<int> bytes,
  required String filename,
  required Duration start,
  required Duration length,
  void Function(double sent)? onProgress,
  http.Client? client,
}) =>
    _sendAuthorized(
      client,
      (httpClient) => _sendCountingProgress(
          httpClient,
          http.MultipartRequest('POST', _stories(backendUrl))
            ..headers.addAll(_authorization(token))
            ..fields['start_ms'] = '${start.inMilliseconds}'
            ..fields['length_ms'] = '${length.inMilliseconds}'
            ..files.add(http.MultipartFile.fromBytes('file', bytes,
                filename: filename)),
          onProgress),
      Story.fromJson,
    );

/// POST .../stories/{id}/view: I watched it (counted once).
Future<void> markStoryViewed(
        {required String backendUrl,
        required String token,
        required int storyId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(_stories(backendUrl, '/$storyId/view'),
          headers: _authorization(token)),
      (_) {},
    );

/// GET .../stories/{id}/viewers: who watched my story, newest first.
Future<List<StoryViewer>> fetchStoryViewers(
        {required String backendUrl,
        required String token,
        required int storyId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(_stories(backendUrl, '/$storyId/viewers'),
          headers: _authorization(token)),
      (data) => [
        for (final v in data['viewers'] as List<dynamic>)
          StoryViewer.fromJson(v as Map<String, dynamic>),
      ],
    );

/// POST .../stories/{id}/reply: a reply or reaction to their story; it goes
/// to our direct chat (so it shows who I am).
Future<ChatMessage> replyToStory(
        {required String backendUrl,
        required String token,
        required int storyId,
        required String body,
        required String clientId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(_stories(backendUrl, '/$storyId/reply'),
          headers: _json(token),
          body: jsonEncode({'body': body, 'client_id': clientId})),
      ChatMessage.fromJson,
    );

/// POST .../stories/{id}/react: a quick reaction, for its owner's Seen by
/// (not a message).
Future<void> reactToStory(
        {required String backendUrl,
        required String token,
        required int storyId,
        required String reaction,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(_stories(backendUrl, '/$storyId/react'),
          headers: _json(token), body: jsonEncode({'reaction': reaction})),
      (_) {},
    );

/// DELETE .../stories/{id}: my story, now.
Future<void> deleteStory(
        {required String backendUrl,
        required String token,
        required int storyId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.delete(_stories(backendUrl, '/$storyId'),
          headers: _authorization(token)),
      (_) {},
    );

/// POST {backendUrl}/chat-media/{id}/view: access to the actual photo or
/// video. The recipient's first open starts its countdown. Throws
/// [MediaExpiredException] once it has expired.
Future<MediaAccess> openChatMedia(
        {required String backendUrl,
        required String token,
        required int attachmentId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _endpoint(backendUrl, '/chat-media/$attachmentId/view'),
          headers: _authorization(token)),
      (data) => MediaAccess.fromJson(data, backendUrl),
    );

/// POST {backendUrl}/messages/album-trade: offers one of my albums, saved
/// once per [clientId].
Future<ChatMessage> offerAlbum(
        {required String backendUrl,
        required String token,
        required int recipientId,
        required int albumId,
        required String clientId,
        int? replyToId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _endpoint(backendUrl, '/messages/album-trade'),
          headers: {
            ..._authorization(token),
            'Content-Type': 'application/json'
          },
          body: jsonEncode({
            'recipient_id': recipientId,
            'album_id': albumId,
            'client_id': clientId,
            if (replyToId != null) 'reply_to_id': replyToId,
          })),
      ChatMessage.fromJson,
    );

/// POST {backendUrl}/album-trades/{id}/respond: I choose one of my albums in
/// return; the trade is completed.
Future<ChatMessage> respondToTrade(
        {required String backendUrl,
        required String token,
        required int tradeId,
        required int albumId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _endpoint(backendUrl, '/album-trades/$tradeId/respond'),
          headers: {
            ..._authorization(token),
            'Content-Type': 'application/json'
          },
          body: jsonEncode({'album_id': albumId})),
      ChatMessage.fromJson,
    );

/// POST {backendUrl}/album-trades/{id}/view: the other person's album of a
/// completed trade. My first open starts my countdown; throws
/// [MediaExpiredException] once it has expired.
Future<TradedAlbumAccess> viewTradedAlbum(
        {required String backendUrl,
        required String token,
        required int tradeId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _endpoint(backendUrl, '/album-trades/$tradeId/view'),
          headers: _authorization(token)),
      (data) => TradedAlbumAccess.fromJson(data, backendUrl),
    );

/// POST {backendUrl}/messages/location: shares where I am now, once. The
/// position goes to the other person; it's never in the database.
Future<ChatMessage> shareLocation({
  required String backendUrl,
  required String token,
  required int recipientId,
  required String clientId,
  required double latitude,
  required double longitude,
  double? accuracy,
  int? replyToId,
  http.Client? client,
}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _endpoint(backendUrl, '/messages/location'),
          headers: {
            ..._authorization(token),
            'Content-Type': 'application/json'
          },
          body: jsonEncode({
            'recipient_id': recipientId,
            'client_id': clientId,
            'latitude': latitude,
            'longitude': longitude,
            if (accuracy != null) 'accuracy': accuracy,
            if (replyToId != null) 'reply_to_id': replyToId,
          })),
      ChatMessage.fromJson,
    );

/// PUT {backendUrl}/messages/{id}/reaction: my reaction (replaces mine);
/// DELETE it when [emoji] is null.
Future<ChatMessage> reactToMessage(
        {required String backendUrl,
        required String token,
        required int messageId,
        required String? emoji,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) {
        final url = _endpoint(backendUrl, '/messages/$messageId/reaction');
        return emoji == null
            ? httpClient.delete(url, headers: _authorization(token))
            : httpClient.put(url,
                headers: {
                  ..._authorization(token),
                  'Content-Type': 'application/json'
                },
                body: jsonEncode({'emoji': emoji}));
      },
      ChatMessage.fromJson,
    );

/// POST {backendUrl}/messages/live-location: asks the other person to share
/// live locations (nothing is shared until they accept).
Future<ChatMessage> requestLiveLocation(
        {required String backendUrl,
        required String token,
        required int recipientId,
        required String clientId,
        int? replyToId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _endpoint(backendUrl, '/messages/live-location'),
          headers: {
            ..._authorization(token),
            'Content-Type': 'application/json'
          },
          body: jsonEncode({
            'recipient_id': recipientId,
            'client_id': clientId,
            if (replyToId != null) 'reply_to_id': replyToId,
          })),
      ChatMessage.fromJson,
    );

/// POST {backendUrl}/live-locations/{id}/{action}: accept, decline, cancel
/// or stop ([reason] "permission" when location access went away).
Future<ChatMessage> liveLocationAction(
        {required String backendUrl,
        required String token,
        required int messageId,
        required String action,
        String? reason,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _endpoint(backendUrl, '/live-locations/$messageId/$action'),
          headers: {
            ..._authorization(token),
            'Content-Type': 'application/json'
          },
          body: reason == null ? null : jsonEncode({'reason': reason})),
      ChatMessage.fromJson,
    );

/// POST {backendUrl}/live-locations/{id}/position: where I am (to the other
/// participant only). Fails once the session isn't active.
Future<void> sendLivePosition(
        {required String backendUrl,
        required String token,
        required int messageId,
        required double latitude,
        required double longitude,
        double? accuracy,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _endpoint(backendUrl, '/live-locations/$messageId/position'),
          headers: {
            ..._authorization(token),
            'Content-Type': 'application/json'
          },
          body: jsonEncode({
            'latitude': latitude,
            'longitude': longitude,
            if (accuracy != null) 'accuracy': accuracy,
          })),
      (_) {},
    );

/// POST {backendUrl}/live-locations/{id}/heartbeat: I'm still here.
Future<void> liveLocationHeartbeat(
        {required String backendUrl,
        required String token,
        required int messageId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _endpoint(backendUrl, '/live-locations/$messageId/heartbeat'),
          headers: _authorization(token)),
      (_) {},
    );

/// GET {backendUrl}/live-locations/{id}: both latest positions while active.
Future<LivePositions> fetchLivePositions(
        {required String backendUrl,
        required String token,
        required int messageId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(
          _endpoint(backendUrl, '/live-locations/$messageId'),
          headers: _authorization(token)),
      (data) {
        SharedPosition? read(Object? p) => p is Map<String, dynamic>
            ? SharedPosition(
                latitude: (p['latitude'] as num).toDouble(),
                longitude: (p['longitude'] as num).toDouble(),
                accuracy: (p['accuracy'] as num?)?.toDouble(),
                at: DateTime.now())
            : null;
        final positions = data['positions'] as Map<String, dynamic>? ?? {};
        return LivePositions(
            me: read(positions['me']), them: read(positions['them']));
      },
    );

/// POST {backendUrl}/location-shares/{id}/stop: I stop sharing a location.
Future<ChatMessage> stopSharingLocation(
        {required String backendUrl,
        required String token,
        required int messageId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _endpoint(backendUrl, '/location-shares/$messageId/stop'),
          headers: _authorization(token)),
      ChatMessage.fromJson,
    );

/// POST {backendUrl}/conversations/{id}/typing: I'm typing ([active]) or
/// stopped; only the other person is told, live.
Future<void> sendTyping(
        {required String backendUrl,
        required String token,
        required int conversationId,
        required bool active,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _endpoint(backendUrl, '/conversations/$conversationId/typing'),
          headers: {
            ..._authorization(token),
            'Content-Type': 'application/json'
          },
          body: jsonEncode({'active': active})),
      (_) {},
    );

/// POST {backendUrl}/media-views/{token}/heartbeat: the viewer is still open.
/// Throws [MediaExpiredException] once the session has ended.
Future<void> mediaViewHeartbeat(
        {required String backendUrl,
        required String token,
        required String viewToken,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _endpoint(backendUrl, '/media-views/$viewToken/heartbeat'),
          headers: _authorization(token)),
      (_) {},
    );

/// POST {backendUrl}/media-views/{token}/end: the viewer was closed; its
/// media can't be loaded any more, and the recipient's countdown starts.
Future<void> endMediaView(
        {required String backendUrl,
        required String token,
        required String viewToken,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _endpoint(backendUrl, '/media-views/$viewToken/end'),
          headers: _authorization(token)),
      (_) {},
    );

/// POST {backendUrl}/album-trades/{id}/interest: my private answer after
/// viewing their album. The "interested" message they got, on a yes (null
/// otherwise, or when it was already answered).
Future<ChatMessage?> answerAlbumInterest(
        {required String backendUrl,
        required String token,
        required int tradeId,
        required bool interested,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _endpoint(backendUrl, '/album-trades/$tradeId/interest'),
          headers: _json(token),
          body: jsonEncode({'interested': interested})),
      (json) => json['message'] == null
          ? null
          : ChatMessage.fromJson(json['message'] as Map<String, dynamic>),
    );

/// POST {backendUrl}/album-trades/{id}/cancel: cancels a pending trade.
Future<ChatMessage> cancelTrade(
        {required String backendUrl,
        required String token,
        required int tradeId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _endpoint(backendUrl, '/album-trades/$tradeId/cancel'),
          headers: _authorization(token)),
      ChatMessage.fromJson,
    );

/// One page of people nearby, nearest first.
class NearbyPage {
  const NearbyPage({required this.people, required this.nextOffset});

  factory NearbyPage.fromJson(Map<String, dynamic> json) => NearbyPage(
        people: [
          for (final person in json['people'] as List<dynamic>)
            Profile.nearby(person as Map<String, dynamic>),
        ],
        nextOffset: json['next_offset'] as int?,
      );

  final List<Profile> people;

  /// Where the next page starts; null on the last page.
  final int? nextOffset;
}

/// One person with all their photos (GET {backendUrl}/explore/people/{id}).
Future<Profile> fetchPerson(
        {required String backendUrl,
        required String token,
        required int userId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(
          _endpoint(backendUrl, '/explore/people/$userId'),
          headers: _authorization(token)),
      Profile.nearby,
    );

/// GET {backendUrl}/explore/nearby?offset=
/// Someone on Explore's map: as Explore shows them, and where their pin
/// goes (blurred by the backend, never where they really are).
class MapPerson {
  const MapPerson(
      {required this.profile, required this.latitude, required this.longitude});

  factory MapPerson.fromJson(Map<String, dynamic> json) {
    final pin = json['map'] as Map<String, dynamic>;
    return MapPerson(
      profile: Profile.nearby(json),
      latitude: (pin['lat'] as num).toDouble(),
      longitude: (pin['lng'] as num).toDouble(),
    );
  }

  final Profile profile;
  final double latitude;
  final double longitude;
}

/// The people in an area of the map ([more]: there were too many; the
/// nearest are these).
class MapArea {
  const MapArea({required this.people, required this.more});

  final List<MapPerson> people;
  final bool more;
}

/// GET .../explore/map: the people in this area, for Explore's map.
Future<MapArea> fetchMapArea(
        {required String backendUrl,
        required String token,
        required double south,
        required double west,
        required double north,
        required double east,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(
          _endpoint(backendUrl, '/explore/map').replace(queryParameters: {
            'south': south.toStringAsFixed(5),
            'west': west.toStringAsFixed(5),
            'north': north.toStringAsFixed(5),
            'east': east.toStringAsFixed(5),
          }),
          headers: _authorization(token)),
      (data) => MapArea(
        people: [
          for (final p in data['people'] as List<dynamic>)
            MapPerson.fromJson(p as Map<String, dynamic>),
        ],
        more: data['more'] as bool? ?? false,
      ),
    );

/// GET .../explore/stories: the stories tray, a page of the people nearby
/// with a story (new ones first).
Future<NearbyPage> fetchStoryPeople(
        {required String backendUrl,
        required String token,
        int offset = 0,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(
          _endpoint(backendUrl, '/explore/stories?offset=$offset'),
          headers: _authorization(token)),
      NearbyPage.fromJson,
    );

Future<NearbyPage> fetchNearby(
        {required String backendUrl,
        required String token,
        int offset = 0,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(
          _endpoint(backendUrl, '/explore/nearby?offset=$offset'),
          headers: _authorization(token)),
      NearbyPage.fromJson,
    );

/// Profile form limits (GET {backendUrl}/profile/config).
Future<ProfileConfig> fetchProfileConfig({
  required String backendUrl,
  required String token,
  http.Client? client,
}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(_endpoint(backendUrl, '/profile/config'),
          headers: _authorization(token)),
      ProfileConfig.fromJson,
    );

/// Records where the user is now (PUT {backendUrl}/profile/me/location).
/// The sign-up location on the account is not changed.
Future<void> updateMyLocation({
  required String backendUrl,
  required String token,
  required double latitude,
  required double longitude,
  http.Client? client,
}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.put(
        _endpoint(backendUrl, '/profile/me/location'),
        headers: {..._authorization(token), 'Content-Type': 'application/json'},
        body: jsonEncode({'latitude': latitude, 'longitude': longitude}),
      ),
      (_) {},
    );

Map<String, String> _authorization(String token) =>
    {'Authorization': 'Bearer $token'};

/// What kind of feedback it is (shown at the start of its title).
enum FeedbackType {
  suggestion('Suggestion'),
  bug('Bug'),
  other('Other');

  const FeedbackType(this.label);
  final String label;
}

/// Feedback I sent, as "My feedback" shows it.
class SentFeedback {
  const SentFeedback({
    required this.id,
    required this.reference,
    required this.title,
    required this.message,
    required this.status,
    required this.sentAt,
    this.screenshotUrls = const [],
    this.teamReply,
  });

  factory SentFeedback.fromJson(Map<String, dynamic> json) => SentFeedback(
        id: json['id'] as int,
        reference: json['request_id'] as String? ?? '',
        title: json['request_title'] as String? ?? '',
        message: json['request_description'] as String? ?? '',
        status: json['request_status'] as String? ?? 'New',
        sentAt:
            DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
        screenshotUrls: [
          for (final a
              in json['request_attachments'] as List<dynamic>? ?? const [])
            if ((a as Map<String, dynamic>)['url'] case final String url) url,
        ],
        teamReply: (json['request_notes'] as String?)?.trim().nullIfEmpty,
      );

  /// "Suggestion", "Bug" or "Other": the "[...]" its title starts with.
  String? get typeLabel => _titleParts?.group(1);

  /// The title without its "[Type] ".
  String get headline => _titleParts?.group(2) ?? title;

  RegExpMatch? get _titleParts =>
      RegExp(r'^\[([^\]]+)\]\s*(.*)$', dotAll: true).firstMatch(title);

  /// Temporary links to its screenshots (they last about an hour).
  final List<String> screenshotUrls;

  /// What the HUNTR team wrote back, if anything.
  final String? teamReply;

  bool get hasScreenshot => screenshotUrls.isNotEmpty;

  final int id;

  /// e.g. FR-2026-0001.
  final String reference;
  final String title;
  final String message;

  /// New, Under Review, More Info Required, Added to Roadmap or Declined.
  final String status;
  final DateTime sentAt;
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

Uri _feedback(String backendUrl, [String path = '']) =>
    _endpoint(backendUrl, '/feature-requests$path');

/// POST .../feature-requests: my feedback, with an optional screenshot. The
/// backend fills in my account's email.
Future<void> sendFeedback({
  required String backendUrl,
  required String token,
  required String title,
  required String message,
  List<int>? screenshot,
  String? screenshotName,
  http.Client? client,
}) =>
    _sendAuthorized(
      client,
      (httpClient) async {
        final request = http.MultipartRequest('POST', _feedback(backendUrl))
          ..headers.addAll(_authorization(token))
          ..fields.addAll({
            'request_title': title,
            'request_description': message,
            'request_priority': 'Low',
          });
        if (screenshot != null) {
          request.files.add(http.MultipartFile.fromBytes(
              'request_file', screenshot,
              filename: screenshotName ?? 'screenshot.png'));
        }
        return http.Response.fromStream(await httpClient.send(request));
      },
      (_) {},
    );

/// GET .../feature-requests/my-requests: what I sent, newest first.
Future<List<SentFeedback>> fetchMyFeedback(
        {required String backendUrl,
        required String token,
        http.Client? client}) =>
    _sendAuthorizedJson(
      client,
      (httpClient) => httpClient.get(
          _feedback(backendUrl, '/my-requests').replace(queryParameters: {
            'page_size': '50',
            'sort_field': 'created_at',
            'sort_direction': 'desc',
          }),
          headers: _authorization(token)),
      (body) => [
        for (final f in body['data'] as List<dynamic>)
          SentFeedback.fromJson(f as Map<String, dynamic>),
      ],
    );

/// Sends a request that needs the session token and reads its `data` field.
Future<T> _sendAuthorized<T>(
  http.Client? client,
  Future<http.Response> Function(http.Client httpClient) send,
  T Function(Map<String, dynamic> data) readData,
) =>
    _sendAuthorizedJson(
        client, send, (body) => readData(body['data'] as Map<String, dynamic>));

/// [_sendAuthorized] for the few responses whose `data` isn't an object
/// (e.g. a list beside `pagination`): reads the whole body.
Future<T> _sendAuthorizedJson<T>(
  http.Client? client,
  Future<http.Response> Function(http.Client httpClient) send,
  T Function(Map<String, dynamic> body) readBody,
) =>
    _sendAuthorizedRaw(
        client,
        send,
        (response) =>
            readBody(jsonDecode(response.body) as Map<String, dynamic>));

/// Sends a request that needs the session token; a successful response goes
/// to [read] as it came (e.g. a file's bytes), anything else is thrown as
/// what it means (an expired session, a block, the backend's message, ...).
Future<T> _sendAuthorizedRaw<T>(
  http.Client? client,
  Future<http.Response> Function(http.Client httpClient) send,
  T Function(http.Response response) read,
) async {
  final httpClient = client ?? http.Client();
  try {
    final response = await send(httpClient);
    _checkRateLimit(response);
    if (response.statusCode == 200) return read(response);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const SessionRejectedException();
    }
    final message = _detailMessage(response.body);
    if (response.statusCode == 409 &&
        (message == blockedByThemMessage || message == blockedByMeMessage)) {
      throw BlockedException(byMe: message == blockedByMeMessage);
    }
    if (response.statusCode == 410) {
      throw MediaExpiredException(
          message ?? 'This photo or video has expired.');
    }
    if (response.statusCode == 422 && message == null) {
      throw ProfileValidationException(_fieldErrors(response.body));
    }
    if (response.statusCode != 200) {
      // Short messages meant for the user (e.g. the photo limit, or a 503
      // "please try again") are shown as they are. An unexpected server
      // error's detail is internal (e.g. "Listing albums failed"), so it
      // gets a plain message instead, as does anything without a message.
      final unexpected =
          response.statusCode >= 500 && response.statusCode != 503;
      throw BackendException(unexpected || message == null
          ? 'Something went wrong on our side. Please try again in a moment.'
          : message);
    }
    // unreachable: every status other than 200 throws above
    throw StateError('Unexpected response ${response.statusCode}');
  } on http.ClientException {
    throw const BackendException('Could not reach the Huntr server.');
  } finally {
    if (client == null) httpClient.close();
  }
}

/// A plain `detail` message from the backend, if it sent one.
String? _detailMessage(String body) {
  try {
    final detail = (jsonDecode(body) as Map<String, dynamic>)['detail'];
    return detail is String && detail.isNotEmpty ? detail : null;
  } on Object {
    return null;
  }
}

/// Reads FastAPI's validation errors (`detail: [{loc: [..., field], msg}]`).
Map<String, String> _fieldErrors(String body) {
  final errors = <String, String>{};
  try {
    final detail = (jsonDecode(body) as Map<String, dynamic>)['detail'];
    if (detail is List) {
      for (final error in detail.whereType<Map<String, dynamic>>()) {
        final location = error['loc'];
        final field = location is List && location.isNotEmpty
            ? location.last.toString()
            : '';
        final message = (error['msg'] as String? ?? 'Invalid value')
            .replaceFirst('Value error, ', '');
        errors.putIfAbsent(field, () => message);
      }
    }
  } on FormatException {
    // Not JSON: no field details to show.
  }
  return errors;
}

// ---- blocking ----

/// Whether I block someone, or they block me.
class BlockStatus {
  const BlockStatus(
      {this.blockedByMe = false,
      this.blockedMe = false,
      this.unblockAvailableAt,
      this.canUnblock = false});

  factory BlockStatus.fromJson(Map<String, dynamic> json) => BlockStatus(
        blockedByMe: json['blocked_by_me'] as bool? ?? false,
        blockedMe: json['blocked_me'] as bool? ?? false,
        unblockAvailableAt: json['unblock_available_at'] == null
            ? null
            : DateTime.parse(json['unblock_available_at'] as String).toLocal(),
        canUnblock: json['can_unblock'] as bool? ?? false,
      );

  static const none = BlockStatus();

  final bool blockedByMe;
  final bool blockedMe;

  /// When I may lift my block (only mine is ever known).
  final DateTime? unblockAvailableAt;
  final bool canUnblock;

  bool get blocked => blockedByMe || blockedMe;
}

/// Someone I block, in my Blocked users list.
class BlockedPerson {
  const BlockedPerson(
      {this.userId,
      required this.name,
      this.photoUrl,
      this.anonymousConversationId,
      this.anonymousAvatar,
      required this.blockedAt,
      required this.unblockAvailableAt,
      required this.canUnblock});

  factory BlockedPerson.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    // someone I only know anonymously: no id, their anonymous name
    final anonymous = json['anonymous'] as Map<String, dynamic>?;
    return BlockedPerson(
      userId: user?['id'] as int?,
      name: (user?['display_name'] as String?)?.trim() ??
          anonymous?['name'] as String? ??
          '',
      photoUrl: user?['photo_url'] as String?,
      anonymousConversationId: anonymous?['conversation_id'] as int?,
      anonymousAvatar: anonymous?['avatar'] as String?,
      blockedAt: DateTime.parse(json['blocked_at'] as String).toLocal(),
      unblockAvailableAt:
          DateTime.parse(json['unblock_available_at'] as String).toLocal(),
      canUnblock: json['can_unblock'] as bool? ?? false,
    );
  }

  /// Null for someone I only know anonymously (see [anonymousConversationId]).
  final int? userId;
  final String name;
  final String? photoUrl;

  /// They declined to show me who they are: unblocked through this
  /// conversation, shown as this animal.
  final int? anonymousConversationId;
  final String? anonymousAvatar;

  /// Tells entries apart (a user id, or the anonymous conversation).
  String get ref =>
      userId != null ? '$userId' : 'anon-$anonymousConversationId';
  final DateTime blockedAt;
  final DateTime unblockAvailableAt;
  final bool canUnblock;
}

/// GET {backendUrl}/blocks/{id}: whether I block them, or they block me.
Future<BlockStatus> fetchBlockStatus(
        {required String backendUrl,
        required String token,
        required int userId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(_endpoint(backendUrl, '/blocks/$userId'),
          headers: _authorization(token)),
      BlockStatus.fromJson,
    );

/// POST {backendUrl}/blocks: I block them (both ways at once).
Future<void> blockUser(
        {required String backendUrl,
        required String token,
        required int userId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(_endpoint(backendUrl, '/blocks'),
          headers: {
            ..._authorization(token),
            'Content-Type': 'application/json'
          },
          body: jsonEncode({'user_id': userId})),
      (_) {},
    );

/// DELETE {backendUrl}/blocks/{id}: I lift my block (only from its date).
Future<void> unblockUser(
        {required String backendUrl,
        required String token,
        required int userId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.delete(
          _endpoint(backendUrl, '/blocks/$userId'),
          headers: _authorization(token)),
      (_) {},
    );

/// GET {backendUrl}/blocks: the people I block.
Future<List<BlockedPerson>> fetchMyBlocks(
        {required String backendUrl,
        required String token,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(_endpoint(backendUrl, '/blocks'),
          headers: _authorization(token)),
      (data) => [
        for (final b in data['blocks'] as List<dynamic>)
          BlockedPerson.fromJson(b as Map<String, dynamic>),
      ],
    );

/// POST .../profile/me/anonymous-name: a new random anonymous name for me,
/// from now on (what I already wrote keeps the old one).
Future<AnonymousName> changeMyAnonymousName(
        {required String backendUrl,
        required String token,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _endpoint(backendUrl, '/profile/me/anonymous-name'),
          headers: _authorization(token)),
      AnonymousName.fromJson,
    );

// ---- Nearby: anonymous posts around me ----

/// Someone's anonymous name and animal, like "SpicyHamster1234" - in
/// anonymous chats and Threads (never who they are).
class AnonymousName {
  const AnonymousName({required this.name, required this.avatar});

  factory AnonymousName.fromJson(Map<String, dynamic> json) => AnonymousName(
      name: json['name'] as String, avatar: json['avatar'] as String);

  final String name;

  /// The animal (see anonymousAnimals).
  final String avatar;
}

/// A tag a Threads post can have, like "Sex" (Looking for) or "Outdoor"
/// (Meet preference).
class NearbyTag {
  const NearbyTag(
      {required this.id,
      required this.slug,
      required this.name,
      required this.category});

  factory NearbyTag.fromJson(Map<String, dynamic> json) => NearbyTag(
      id: json['id'] as int,
      slug: json['slug'] as String,
      name: json['name'] as String,
      category: json['category'] as String);

  final int id;
  final String slug;
  final String name;

  /// looking_for or meet_preference.
  final String category;
}

/// One kind of tag (Looking for, Meet preference) and its tags, in order.
class NearbyTagCategory {
  const NearbyTagCategory(
      {required this.key, required this.label, required this.tags});

  factory NearbyTagCategory.fromJson(Map<String, dynamic> json) =>
      NearbyTagCategory(
        key: json['key'] as String,
        label: json['label'] as String,
        tags: [
          for (final t in json['tags'] as List)
            NearbyTag.fromJson(t as Map<String, dynamic>),
        ],
      );

  final String key;
  final String label;
  final List<NearbyTag> tags;
}

/// A Nearby post as I see it.
class NearbyPost {
  const NearbyPost({
    required this.id,
    required this.author,
    required this.body,
    required this.distanceM,
    required this.createdAt,
    required this.likeCount,
    required this.liked,
    required this.commentCount,
    required this.mine,
    this.radiusM,
    this.tags = const [],
  });

  factory NearbyPost.fromJson(Map<String, dynamic> json) => NearbyPost(
        id: json['id'] as int,
        author: AnonymousName.fromJson(json),
        body: json['body'] as String,
        distanceM: json['distance_m'] as int?,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        likeCount: json['like_count'] as int? ?? 0,
        liked: json['liked'] as bool? ?? false,
        commentCount: json['comment_count'] as int? ?? 0,
        mine: json['mine'] as bool? ?? false,
        radiusM: json['radius_m'] as int?,
        tags: [
          for (final t in json['tags'] as List? ?? const [])
            NearbyTag.fromJson(t as Map<String, dynamic>),
        ],
      );

  final int id;
  final AnonymousName author;
  final String body;

  /// From me to where it was posted, to 10 m (mine too).
  final int? distanceM;
  final DateTime createdAt;
  final int likeCount;
  final bool liked;
  final int commentCount;
  final bool mine;

  /// How far it reaches (mine only).
  final int? radiusM;

  /// Its tags: Looking for first, then Meet preference.
  final List<NearbyTag> tags;

  NearbyPost copyWith({int? likeCount, bool? liked, int? commentCount}) =>
      NearbyPost(
        id: id,
        author: author,
        body: body,
        distanceM: distanceM,
        createdAt: createdAt,
        likeCount: likeCount ?? this.likeCount,
        liked: liked ?? this.liked,
        commentCount: commentCount ?? this.commentCount,
        mine: mine,
        radiusM: radiusM,
        tags: tags,
      );
}

/// A comment on a Nearby post (with its replies, when it's a top-level one).
class NearbyComment {
  const NearbyComment({
    required this.id,
    required this.parentId,
    required this.author,
    required this.body,
    required this.distanceM,
    required this.createdAt,
    required this.likeCount,
    required this.liked,
    required this.mine,
    required this.byAuthor,
    this.replies = const [],
  });

  factory NearbyComment.fromJson(Map<String, dynamic> json) => NearbyComment(
        id: json['id'] as int,
        parentId: json['parent_id'] as int?,
        author: AnonymousName.fromJson(json),
        body: json['body'] as String,
        distanceM: json['distance_m'] as int?,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        likeCount: json['like_count'] as int? ?? 0,
        liked: json['liked'] as bool? ?? false,
        mine: json['mine'] as bool? ?? false,
        byAuthor: json['by_author'] as bool? ?? false,
        replies: [
          for (final r in json['replies'] as List? ?? const [])
            NearbyComment.fromJson(r as Map<String, dynamic>),
        ],
      );

  final int id;
  final int? parentId;
  final AnonymousName author;
  final String body;
  final int? distanceM;
  final DateTime createdAt;
  final int likeCount;
  final bool liked;
  final bool mine;

  /// Written by the post's author (shown by their name on it).
  final bool byAuthor;
  final List<NearbyComment> replies;
}

/// A post and its discussion: newest comments first, replies oldest first.
class NearbyDiscussion {
  const NearbyDiscussion({required this.post, required this.comments});

  factory NearbyDiscussion.fromJson(Map<String, dynamic> json) =>
      NearbyDiscussion(
        post: NearbyPost.fromJson(json['post'] as Map<String, dynamic>),
        comments: [
          for (final c in json['comments'] as List)
            NearbyComment.fromJson(c as Map<String, dynamic>),
        ],
      );

  final NearbyPost post;
  final List<NearbyComment> comments;
}

/// A page of the Nearby feed.
class NearbyFeedPage {
  const NearbyFeedPage({required this.posts, required this.nextOffset});

  final List<NearbyPost> posts;
  final int? nextOffset;
}

/// My location isn't known to the backend yet (Nearby needs it).
class NearbyNoLocationException extends BackendException {
  const NearbyNoLocationException(super.message);
}

Uri _nearby(String backendUrl, [String path = '']) =>
    _endpoint(backendUrl, '/nearby$path');

/// Nearby's 409 for "no location" is its own exception; others as they come.
Future<T> _nearbyCall<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on BackendException catch (error) {
    if (error is! SessionRejectedException &&
        error.message.toLowerCase().contains('turn on your location')) {
      throw NearbyNoLocationException(error.message);
    }
    rethrow;
  }
}

/// GET .../nearby/posts: posts I may see, nearest ("nearby") or newest
/// ("latest") first, optionally only within [withinM] of me.
Future<NearbyFeedPage> fetchNearbyPosts(
        {required String backendUrl,
        required String token,
        String sort = 'nearby',
        int? withinM,
        int offset = 0,
        http.Client? client}) =>
    _nearbyCall(() => _sendAuthorized(
          client,
          (httpClient) => httpClient.get(
              _nearby(backendUrl, '/posts').replace(queryParameters: {
                'sort': sort,
                'offset': '$offset',
                if (withinM != null) 'within_m': '$withinM',
              }),
              headers: _authorization(token)),
          (data) => NearbyFeedPage(
            posts: [
              for (final p in data['posts'] as List)
                NearbyPost.fromJson(p as Map<String, dynamic>),
            ],
            nextOffset: data['next_offset'] as int?,
          ),
        ));

/// GET .../nearby/mine: my live posts, newest first.
Future<NearbyFeedPage> fetchMyNearbyPosts(
        {required String backendUrl,
        required String token,
        int offset = 0,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(
          _nearby(backendUrl, '/mine')
              .replace(queryParameters: {'offset': '$offset'}),
          headers: _authorization(token)),
      (data) => NearbyFeedPage(
        posts: [
          for (final p in data['posts'] as List)
            NearbyPost.fromJson(p as Map<String, dynamic>),
        ],
        nextOffset: data['next_offset'] as int?,
      ),
    );

/// POST .../nearby/posts: my post, as [as] (the previewed name).
Future<NearbyPost> createNearbyPost(
        {required String backendUrl,
        required String token,
        required String body,
        required int radiusM,
        AnonymousName? as,
        List<int> tagIds = const [],
        http.Client? client}) =>
    _nearbyCall(() => _sendAuthorized(
          client,
          (httpClient) => httpClient.post(_nearby(backendUrl, '/posts'),
              headers: _json(token),
              body: jsonEncode({
                'body': body,
                'radius_m': radiusM,
                if (tagIds.isNotEmpty) 'tag_ids': tagIds,
                if (as != null) 'name': as.name,
                if (as != null) 'avatar': as.avatar,
              })),
          NearbyPost.fromJson,
        ));

/// GET .../nearby/tags: the tags a post can have, by category.
Future<List<NearbyTagCategory>> fetchNearbyTags(
        {required String backendUrl,
        required String token,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.get(_nearby(backendUrl, '/tags'),
          headers: _authorization(token)),
      (json) => [
        for (final c in json['categories'] as List)
          NearbyTagCategory.fromJson(c as Map<String, dynamic>),
      ],
    );

/// GET .../nearby/posts/{id}: the post and its discussion.
Future<NearbyDiscussion> fetchNearbyDiscussion(
        {required String backendUrl,
        required String token,
        required int postId,
        http.Client? client}) =>
    _nearbyCall(() => _sendAuthorized(
          client,
          (httpClient) => httpClient.get(_nearby(backendUrl, '/posts/$postId'),
              headers: _authorization(token)),
          NearbyDiscussion.fromJson,
        ));

/// POST .../nearby/posts/{id}/comments: my comment, or reply ([parentId]);
/// the discussion as it is now.
Future<NearbyDiscussion> commentOnNearbyPost(
        {required String backendUrl,
        required String token,
        required int postId,
        required String body,
        int? parentId,
        http.Client? client}) =>
    _nearbyCall(() => _sendAuthorized(
          client,
          (httpClient) => httpClient.post(
              _nearby(backendUrl, '/posts/$postId/comments'),
              headers: _json(token),
              body: jsonEncode({'body': body, 'parent_id': parentId})),
          NearbyDiscussion.fromJson,
        ));

/// POST/DELETE .../like on a post (or one of its comments): (hearts, mine).
Future<({int count, bool liked})> likeNearby(
        {required String backendUrl,
        required String token,
        required int postId,
        int? commentId,
        required bool like,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) {
        final url = _nearby(
            backendUrl,
            commentId == null
                ? '/posts/$postId/like'
                : '/posts/$postId/comments/$commentId/like');
        return like
            ? httpClient.post(url, headers: _authorization(token))
            : httpClient.delete(url, headers: _authorization(token));
      },
      (data) =>
          (count: data['like_count'] as int, liked: data['liked'] as bool),
    );

/// DELETE my post, or ([commentId]) my comment.
Future<void> deleteNearby(
        {required String backendUrl,
        required String token,
        int? postId,
        int? commentId,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.delete(
          _nearby(backendUrl,
              commentId == null ? '/posts/$postId' : '/comments/$commentId'),
          headers: _authorization(token)),
      (_) {},
    );

/// Reports a post (or one of its comments); it's hidden from me after.
Future<void> reportNearby(
        {required String backendUrl,
        required String token,
        required int postId,
        int? commentId,
        required String reason,
        http.Client? client}) =>
    _sendAuthorized(
      client,
      (httpClient) => httpClient.post(
          _nearby(
              backendUrl,
              commentId == null
                  ? '/posts/$postId/report'
                  : '/posts/$postId/comments/$commentId/report'),
          headers: _json(token),
          body: jsonEncode({'reason': reason})),
      (_) {},
    );
