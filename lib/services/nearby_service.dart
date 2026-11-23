import 'package:http/http.dart' as http;

import '../config/google_oauth_config.dart';
import 'huntr_backend.dart' as backend;
import '../config/store_build.dart';
import 'huntr_backend.dart'
    show
        NearbyDiscussion,
        AnonymousName,
        NearbyFeedPage,
        NearbyMedia,
        NearbyPost,
        NearbyTagCategory;

/// Nearby: anonymous text posts for the people around me (the backend
/// decides who sees what, and never says who anyone is).
class NearbyService {
  const NearbyService();

  /// The distances a post can reach, in metres (the backend's RADII_M).
  static const radii = [500, 1000, 3000, 5000, 10000];

  /// The longest post or comment.
  static const maxLength = 500;

  /// The longest subject (a Reddit title's length).
  static const subjectMaxLength = 300;

  /// The largest photo or video (the backend's
  /// NEARBY_USER_MEDIA_MAX_UPLOAD_BYTES), and the longest video
  /// (NEARBY_USER_VIDEO_MAX_SECONDS).
  static const maxUploadBytes = 300 * 1024 * 1024;
  static const maxVideoLength = Duration(minutes: 30);

  Future<String> _url() => GoogleOAuthConfig.loadBackendUrl();

  Future<NearbyFeedPage> feed(String token,
          {String sort = 'nearby', int? withinM, int offset = 0}) async =>
      backend.fetchNearbyPosts(
          backendUrl: await _url(),
          token: token,
          sort: sort,
          withinM: withinM,
          offset: offset);

  /// My live posts, newest first.
  Future<NearbyFeedPage> mine(String token, {int offset = 0}) async =>
      backend.fetchMyNearbyPosts(
          backendUrl: await _url(), token: token, offset: offset);

  /// The live threads I reposted, the latest repost first.
  Future<NearbyFeedPage> reposts(String token, {int offset = 0}) async =>
      backend.fetchMyNearbyReposts(
          backendUrl: await _url(), token: token, offset: offset);

  /// Someone's anonymous profile: their threads ([reposts]: what they
  /// reposted) under the anonymous name they wrote post [postId] (or its
  /// comment [commentId]) with.
  Future<NearbyFeedPage> authorThreads(String token,
          {required int postId,
          int? commentId,
          required bool reposts,
          int offset = 0}) async =>
      backend.fetchNearbyAuthorThreads(
          backendUrl: await _url(),
          token: token,
          postId: postId,
          commentId: commentId,
          reposts: reposts,
          offset: offset);

  /// Reposts someone else's thread, or takes my repost back.
  Future<({int count, bool reposted})> repost(String token, int postId,
          {required bool repost}) async =>
      backend.repostNearby(
          backendUrl: await _url(),
          token: token,
          postId: postId,
          repost: repost);

  /// My post's text, who sees it ([radiusM] null: everyone on HUNTR) and
  /// tags, from now; the post as it is now.
  Future<NearbyPost> edit(String token,
          {required int postId,
          required String body,
          required int? radiusM,
          String? subject,
          List<int> tagIds = const []}) async =>
      backend.editNearbyPost(
          backendUrl: await _url(),
          token: token,
          postId: postId,
          body: body,
          radiusM: radiusM,
          subject: subject,
          tagIds: tagIds);

  /// [radiusM] null: for everyone on HUNTR.
  Future<NearbyPost> post(String token,
          {required String body,
          required int? radiusM,
          String? subject,
          AnonymousName? as,
          List<int> tagIds = const [],
          int? mediaId}) async =>
      backend.createNearbyPost(
          backendUrl: await _url(),
          token: token,
          body: body,
          radiusM: radiusM,
          subject: subject,
          as: as,
          tagIds: tagIds,
          mediaId: mediaId);

  /// A photo or video I chose for my next post, before
  /// its file is sent.
  Future<NearbyMedia> reserveMedia(String token,
          {required bool isVideo}) async =>
      backend.reserveNearbyMedia(
          backendUrl: await _url(), token: token, isVideo: isVideo);

  /// Its file; closing [client] stops it.
  Future<NearbyMedia> uploadMedia(String token,
          {required int mediaId,
          required List<int> bytes,
          required String filename,
          void Function(double sent)? onProgress,
          http.Client? client}) async =>
      backend.uploadNearbyMedia(
          backendUrl: await _url(),
          token: token,
          mediaId: mediaId,
          bytes: bytes,
          filename: filename,
          onProgress: onProgress,
          client: client);

  /// One I chose that isn't posted, or that's on my post but isn't ready.
  Future<void> removeMedia(String token, int mediaId) async =>
      backend.removeNearbyMedia(
          backendUrl: await _url(), token: token, mediaId: mediaId);

  /// The tags a post can have, by category (Looking for, Meet preference).
  Future<List<NearbyTagCategory>> tags(String token) async =>
      backend.fetchNearbyTags(backendUrl: await _url(), token: token);

  Future<NearbyDiscussion> discussion(String token, int postId) async =>
      backend.fetchNearbyDiscussion(
          backendUrl: await _url(), token: token, postId: postId);

  Future<NearbyDiscussion> comment(String token, int postId,
          {required String body, int? parentId}) async =>
      backend.commentOnNearbyPost(
          backendUrl: await _url(),
          token: token,
          postId: postId,
          body: body,
          parentId: parentId);

  Future<({int count, bool liked})> like(String token, int postId,
          {int? commentId, required bool like}) async =>
      backend.likeNearby(
          backendUrl: await _url(),
          token: token,
          postId: postId,
          commentId: commentId,
          like: like);

  Future<void> delete(String token, {int? postId, int? commentId}) async =>
      backend.deleteNearby(
          backendUrl: await _url(),
          token: token,
          postId: postId,
          commentId: commentId);

  Future<void> report(String token, int postId,
          {int? commentId, required String reason}) async =>
      backend.reportNearby(
          backendUrl: await _url(),
          token: token,
          postId: postId,
          commentId: commentId,
          reason: reason);
}

/// "320 m", "2.3 km", or "here" when it's that close (the backend gives
/// metres to 10 m, to where it was posted).
String nearbyDistanceLabel(int metres) => metres < 10
    ? 'here'
    : metres < 1000
        ? '$metres m'
        : '${(metres / 1000).toStringAsFixed(metres % 1000 == 0 ? 0 : 1)} km';

/// "Within 5 km", "Within 500 m".
String nearbyRadiusLabel(int metres) =>
    metres < 1000 ? '$metres m' : '${metres ~/ 1000} km';

/// "just now", "12 min ago", "3 h ago", "2 d ago".
String nearbyAgo(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// What's wrong with a subject, as the backend says it (null: nothing):
/// it's needed, at most [NearbyService.subjectMaxLength] characters, of
/// letters (any language), numbers, spaces and . , ! ? ' " - ( ) : ; & /
/// only - no emoji or other symbols.
String? nearbySubjectProblem(String subject) {
  final text = subject.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (text.isEmpty) return 'Add a subject.';
  if (text.length > NearbyService.subjectMaxLength) {
    return 'Keep the subject to ${NearbyService.subjectMaxLength} characters.';
  }
  if (!_subjectAllowed.hasMatch(text)) return nearbySubjectRule;
  return null;
}

const nearbySubjectRule = "A subject can have letters, numbers, spaces and "
    ". , ! ? ' \" - ( ) : ; & / only.";

/// Letters and their accents, plain digits, spaces and basic punctuation
/// (with the curly quotes and dashes phones type) - never "fancy font"
/// letters (Mathematical Alphanumeric Symbols).
final _subjectAllowed = RegExp(
    r"^(?:(?![\u{1D400}-\u{1D7FF}])[\p{L}\p{M}\p{Nd} .,!?'"
    '"'
    r"\-():;&/\u2018\u2019\u201C\u201D\u2013\u2014])+$",
    unicode: true);

/// Whether a thread is shown in this build: in an App Store or Google Play
/// build, never one tagged NSFW (both stores reject explicit media).
bool nearbyThreadShown(NearbyPost post) => !(isStoreBuild && post.nsfw);
