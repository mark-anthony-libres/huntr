import '../config/google_oauth_config.dart';
import '../models/models.dart';
import 'huntr_backend.dart';

/// Loads and saves the signed-in user's profile on the backend.
class ProfileService {
  const ProfileService();

  Future<MyProfile> fetchMine(String token) async => fetchMyProfile(
      backendUrl: await GoogleOAuthConfig.loadBackendUrl(), token: token);

  Future<ProfileConfig> fetchConfig(String token) async => fetchProfileConfig(
      backendUrl: await GoogleOAuthConfig.loadBackendUrl(), token: token);

  Future<MyProfile> saveOnboarding(
          String token, OnboardingAnswers answers) async =>
      saveMyOnboarding(
        backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
        token: token,
        displayName: _blankToNull(answers.displayName),
        age: answers.age,
        latitude: answers.location.latitude,
        longitude: answers.location.longitude,
        lookingFor: _choiceNames(answers.lookingFor),
      );

  Future<MyProfile> updateProfile(String token, ProfileEdit edit) async =>
      updateMyProfile(
        backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
        token: token,
        displayName: _blankToNull(edit.displayName),
        bio: _blankToNull(edit.bio),
        age: edit.age,
        lookingFor: _choiceNames(edit.lookingFor),
        stats: edit.stats,
      );

  /// The one sexual position my profile shows (null: do not show).
  Future<SexualPosition?> updatePosition(
          String token, SexualPosition? position) async =>
      SexualPosition.parse(await updateMyPosition(
        backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
        token: token,
        sexualPosition: position?.apiName,
      ));

  /// Saves whichever privacy settings are given.
  Future<PrivacySettings> updatePrivacy(String token,
          {bool? showOnline,
          bool? showDistance,
          bool? showOnMap,
          bool? notifyTaps,
          bool? notifyMessages,
          bool? notifyStoryReplies}) async =>
      updateMyPrivacy(
        backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
        token: token,
        showOnline: showOnline,
        showDistance: showDistance,
        showOnMap: showOnMap,
        notifyTaps: notifyTaps,
        notifyMessages: notifyMessages,
        notifyStoryReplies: notifyStoryReplies,
      );

  /// A new random anonymous name for me, from now on.
  Future<AnonymousName> changeAnonymousName(String token) async =>
      changeMyAnonymousName(
          backendUrl: await GoogleOAuthConfig.loadBackendUrl(), token: token);

  /// Permanently deletes the account and everything stored about it.
  Future<void> deleteAccount(String token) async => deleteMyAccount(
      backendUrl: await GoogleOAuthConfig.loadBackendUrl(), token: token);

  Future<void> updateLocation(String token, GeoPoint location) async =>
      updateMyLocation(
        backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
        token: token,
        latitude: location.latitude,
        longitude: location.longitude,
      );

  static String? _blankToNull(String value) =>
      value.trim().isEmpty ? null : value.trim();

  static List<String> _choiceNames(Set<LookingFor> choices) =>
      [for (final choice in choices) choice.name];
}
