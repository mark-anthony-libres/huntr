import '../config/google_oauth_config.dart';
import 'huntr_backend.dart' as backend;
import 'huntr_backend.dart' show ChangelogNews, ChangelogPage;

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
}
