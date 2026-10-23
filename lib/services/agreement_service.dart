import '../config/google_oauth_config.dart';
import 'huntr_backend.dart';

/// Loads the terms & community guidelines from the backend.
class AgreementService {
  const AgreementService();

  Future<String> fetch() async =>
      fetchAgreement(backendUrl: await GoogleOAuthConfig.loadBackendUrl());

  Future<String> fetchGuidelines() async => fetchCommunityGuidelines(
      backendUrl: await GoogleOAuthConfig.loadBackendUrl());

  /// Deactivates the signed-in user's account.
  Future<void> decline(String token) async => declineAgreement(
      backendUrl: await GoogleOAuthConfig.loadBackendUrl(), token: token);
}
