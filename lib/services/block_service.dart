import '../config/google_oauth_config.dart';
import 'huntr_backend.dart' as backend;
import 'huntr_backend.dart' show BlockStatus, BlockedPerson;

/// Blocking on the backend (which enforces it everywhere).
class BlockService {
  const BlockService();

  Future<BlockStatus> status(String token, int userId) async =>
      backend.fetchBlockStatus(
          backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
          token: token,
          userId: userId);

  Future<void> block(String token, int userId) async => backend.blockUser(
      backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
      token: token,
      userId: userId);

  Future<void> unblock(String token, int userId) async => backend.unblockUser(
      backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
      token: token,
      userId: userId);

  /// Unblock the anonymous sender of this conversation (no user id).
  Future<void> unblockAnonymous(String token, int conversationId) async =>
      backend.unblockAnonymous(
          backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
          token: token,
          conversationId: conversationId);

  Future<List<BlockedPerson>> mine(String token) async => backend.fetchMyBlocks(
      backendUrl: await GoogleOAuthConfig.loadBackendUrl(), token: token);
}
