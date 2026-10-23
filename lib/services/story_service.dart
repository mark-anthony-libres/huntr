import '../config/google_oauth_config.dart';
import 'huntr_backend.dart' as backend;
import 'huntr_backend.dart' show ChatMessage, Story, StoryViewer;

/// Stories (My Day): short public videos that disappear after 24 hours.
class StoryService {
  const StoryService();

  /// What's kept of a longer video (the backend cuts it).
  static const maxLength = Duration(seconds: 5);

  /// How long a story stays up.
  static const lifetime = Duration(hours: 24);

  /// The longest file (the website on a computer) that can be trimmed to a
  /// story; recordings are never longer than [maxLength] anyway.
  static const maxSourceLength = Duration(minutes: 3);

  /// The most stories one person can have up at once (the backend's
  /// STORY_MAX_ACTIVE; it refuses more either way).
  static const maxActive = 10;

  /// The largest video that can be uploaded.
  static const maxUploadBytes = 50 * 1024 * 1024;

  Future<String> _url() => GoogleOAuthConfig.loadBackendUrl();

  Future<List<Story>> of(String token, int userId) async => backend
      .fetchStoriesOf(backendUrl: await _url(), token: token, userId: userId);

  Future<List<Story>> mine(String token) async =>
      backend.fetchMyStories(backendUrl: await _url(), token: token);

  Future<Story> post(String token,
          {required List<int> bytes,
          required String filename,
          required Duration start,
          required Duration length,
          void Function(double sent)? onProgress}) async =>
      backend.postStory(
          backendUrl: await _url(),
          token: token,
          bytes: bytes,
          filename: filename,
          start: start,
          length: length,
          onProgress: onProgress);

  Future<void> markViewed(String token, int storyId) async =>
      backend.markStoryViewed(
          backendUrl: await _url(), token: token, storyId: storyId);

  Future<List<StoryViewer>> viewers(String token, int storyId) async =>
      backend.fetchStoryViewers(
          backendUrl: await _url(), token: token, storyId: storyId);

  Future<void> delete(String token, int storyId) async => backend.deleteStory(
      backendUrl: await _url(), token: token, storyId: storyId);

  /// A quick reaction to their story: its owner sees it in Seen by.
  Future<void> react(String token, int storyId, String reaction) async =>
      backend.reactToStory(
          backendUrl: await _url(),
          token: token,
          storyId: storyId,
          reaction: reaction);

  /// A reply to their story, in our direct chat.
  Future<ChatMessage> reply(String token, int storyId,
          {required String body, required String clientId}) async =>
      backend.replyToStory(
          backendUrl: await _url(),
          token: token,
          storyId: storyId,
          body: body,
          clientId: clientId);
}
