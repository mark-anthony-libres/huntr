import '../config/google_oauth_config.dart';
import 'huntr_backend.dart' as backend;
import 'huntr_backend.dart'
    show NearbyDiscussion, NearbyName, NearbyFeedPage, NearbyPost;

/// Nearby: anonymous text posts for the people around me (the backend
/// decides who sees what, and never says who anyone is).
class NearbyService {
  const NearbyService();

  /// The distances a post can reach, in metres (the backend's RADII_M).
  static const radii = [500, 1000, 3000, 5000, 10000];

  /// The longest post or comment.
  static const maxLength = 500;

  Future<String> _url() => GoogleOAuthConfig.loadBackendUrl();

  Future<NearbyFeedPage> feed(String token,
          {String sort = 'nearby', int? withinM, int offset = 0}) async =>
      backend.fetchNearbyPosts(
          backendUrl: await _url(),
          token: token,
          sort: sort,
          withinM: withinM,
          offset: offset);

  Future<NearbyName> previewName(String token) async =>
      backend.fetchNearbyIdentity(backendUrl: await _url(), token: token);

  Future<NearbyPost> post(String token,
          {required String body, required int radiusM, NearbyName? as}) async =>
      backend.createNearbyPost(
          backendUrl: await _url(),
          token: token,
          body: body,
          radiusM: radiusM,
          as: as);

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
