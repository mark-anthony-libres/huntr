import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the signed-in user's backend session token is kept between launches.
abstract class SessionStore {
  Future<String?> readToken();
  Future<void> saveToken(String token);
  Future<void> clearToken();
}

/// Keeps the token in the platform's secure storage (Keychain / Keystore;
/// encrypted browser storage on web).
class SecureSessionStore implements SessionStore {
  const SecureSessionStore();

  static const _tokenKey = 'huntr_session_token';
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  @override
  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  @override
  Future<void> clearToken() => _storage.delete(key: _tokenKey);
}
