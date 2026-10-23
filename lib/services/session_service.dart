import '../config/google_oauth_config.dart';
import 'huntr_backend.dart';
import 'session_store.dart';

/// Keeps the backend session token across launches and checks it with the
/// backend before the app trusts it.
class SessionService {
  const SessionService({this.store = const SecureSessionStore()});

  final SessionStore store;

  /// The saved token, if the backend still accepts it. A token the backend
  /// rejects is deleted. Throws [BackendException] when the backend
  /// can't be asked; the token is kept so a later launch can retry.
  Future<String?> restoreVerifiedToken() async {
    final token = await store.readToken();
    if (token == null) return null;
    final backendUrl = await GoogleOAuthConfig.loadBackendUrl();
    if (backendUrl.isEmpty) return null;
    if (await isBackendSessionValid(backendUrl: backendUrl, token: token)) {
      return token;
    }
    await store.clearToken();
    return null;
  }

  Future<void> remember(String token) => store.saveToken(token);

  Future<void> forget() => store.clearToken();

  /// Ends the session on the backend (best effort: offline still logs out
  /// here), then forgets it on this device.
  Future<void> logOut(String token) async {
    try {
      final backendUrl = await GoogleOAuthConfig.loadBackendUrl();
      if (backendUrl.isNotEmpty) {
        await logOutOfBackend(backendUrl: backendUrl, token: token);
      }
    } catch (_) {
      // the server is unreachable: it can't use this device's token any
      // more anyway once it's forgotten below
    }
    await forget();
  }
}
