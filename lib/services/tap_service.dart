import '../config/google_oauth_config.dart';
import 'huntr_backend.dart' as backend;
import 'huntr_backend.dart' show ReceivedTap, TapResponse, ViewerPage;

/// Taps on the backend: tapping someone, my Tap inbox, and responding; and
/// my profile's viewers (the Viewers tab beside it).
class TapService {
  const TapService();

  Future<String> _url() => GoogleOAuthConfig.loadBackendUrl();

  Future<List<ReceivedTap>> fetchInbox(String token) async =>
      backend.fetchTapInbox(backendUrl: await _url(), token: token);

  Future<void> send(String token, int recipientId) async => backend.sendTap(
      backendUrl: await _url(), token: token, recipientId: recipientId);

  /// I opened their profile (one [visitId] per opening).
  Future<void> recordView(String token, int userId, String visitId) async =>
      backend.recordProfileView(
          backendUrl: await _url(),
          token: token,
          userId: userId,
          visitId: visitId);

  /// How many people viewed my profile since I last opened Viewers.
  Future<int> fetchNewViewerCount(String token) async => backend
      .fetchNewProfileViewerCount(backendUrl: await _url(), token: token);

  Future<void> markViewersSeen(String token) async =>
      backend.markProfileViewersSeen(backendUrl: await _url(), token: token);

  Future<ViewerPage> fetchViewers(String token, {int offset = 0}) async =>
      backend.fetchProfileViewers(
          backendUrl: await _url(), token: token, offset: offset);

  Future<void> markRead(String token, int tapId) async =>
      backend.markTapRead(backendUrl: await _url(), token: token, tapId: tapId);

  Future<TapResponse> respond(String token, int tapId,
          {required String body, required String clientId}) async =>
      backend.respondToTap(
          backendUrl: await _url(),
          token: token,
          tapId: tapId,
          body: body,
          clientId: clientId);
}
