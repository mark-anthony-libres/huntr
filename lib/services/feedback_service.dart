import '../config/google_oauth_config.dart';
import 'huntr_backend.dart' as backend;
import 'huntr_backend.dart' show FeedbackType, SentFeedback;

/// Feedback and suggestions sent from the app (the backend keeps them for
/// the team; nothing is emailed unless a recipient is set there).
class FeedbackService {
  const FeedbackService();

  /// Longest message the backend takes.
  static const maxMessageLength = 2000;

  Future<String> _url() => GoogleOAuthConfig.loadBackendUrl();

  Future<void> send(String token,
          {required FeedbackType type,
          required String message,
          List<int>? screenshot,
          String? screenshotName}) async =>
      backend.sendFeedback(
          backendUrl: await _url(),
          token: token,
          title: titleFor(type, message),
          message: message,
          screenshot: screenshot,
          screenshotName: screenshotName);

  Future<List<SentFeedback>> fetchMine(String token) async =>
      backend.fetchMyFeedback(backendUrl: await _url(), token: token);

  /// The title the team sees: the kind, then the message's first line.
  static String titleFor(FeedbackType type, String message) {
    final firstLine = message.trim().split('\n').first.trim();
    final short =
        firstLine.length > 100 ? '${firstLine.substring(0, 100)}…' : firstLine;
    return '[${type.label}] $short';
  }
}
