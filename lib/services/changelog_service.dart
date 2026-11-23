import '../config/google_oauth_config.dart';
import 'huntr_backend.dart' as backend;
import 'huntr_backend.dart'
    show ChangelogDiscussion, ChangelogNews, ChangelogPage;

/// HUNTR's changelog (What's new): the entries, and what's new for me.
class ChangelogService {
  const ChangelogService();

  Future<String> _url() => GoogleOAuthConfig.loadBackendUrl();

  /// The API address the entries' photos and videos are under.
  Future<String> backendUrl() => _url();

  Future<ChangelogPage> entries(String token, {int offset = 0}) async => backend
      .fetchChangelog(backendUrl: await _url(), token: token, offset: offset);

  Future<ChangelogNews> news(String token) async =>
      backend.fetchChangelogNews(backendUrl: await _url(), token: token);

  Future<ChangelogNews> markSeen(String token, int entryId) async =>
      backend.markChangelogSeen(
          backendUrl: await _url(), token: token, entryId: entryId);

  /// The longest comment.
  static const commentMaxLength = 500;

  Future<ChangelogDiscussion> comments(String token, int entryId) async =>
      backend.fetchChangelogDiscussion(
          backendUrl: await _url(), token: token, entryId: entryId);

  Future<ChangelogDiscussion> comment(String token, int entryId, String body,
          {int? parentId}) async =>
      backend.addChangelogComment(
          backendUrl: await _url(),
          token: token,
          entryId: entryId,
          body: body,
          parentId: parentId);

  Future<(int, bool)> like(String token, int commentId, bool liked) async =>
      backend.setChangelogCommentLike(
          backendUrl: await _url(),
          token: token,
          commentId: commentId,
          liked: liked);

  Future<void> delete(String token, int commentId) async =>
      backend.deleteChangelogComment(
          backendUrl: await _url(), token: token, commentId: commentId);

  Future<void> report(String token, int commentId, String reason) async =>
      backend.reportChangelogComment(
          backendUrl: await _url(),
          token: token,
          commentId: commentId,
          reason: reason);
}
