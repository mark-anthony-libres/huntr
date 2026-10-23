import '../config/google_oauth_config.dart';
import '../models/models.dart' show Profile;
import 'huntr_backend.dart' as backend;
import 'huntr_backend.dart'
    show
        AnonymousProfile,
        ChatMessage,
        ConversationPage,
        GifPage,
        MessageTarget,
        UnmatchedPerson,
        RevealAnswer,
        MediaAccess,
        MessagePage,
        TradedAlbumAccess,
        LivePositions;

/// Direct messages on the backend.
class MessagingService {
  const MessagingService();

  Future<String> _url() => GoogleOAuthConfig.loadBackendUrl();

  /// A page of my direct conversations ([before]: where the last one ended).
  Future<ConversationPage> fetchConversations(String token,
          {String? before}) async =>
      backend.fetchConversations(
          backendUrl: await _url(), token: token, before: before);

  // ---- anonymous ----

  /// A page of my anonymous conversations.
  Future<ConversationPage> fetchAnonymousConversations(String token,
          {String? before}) async =>
      backend.fetchAnonymousConversations(
          backendUrl: await _url(), token: token, before: before);

  Future<ChatMessage> sendAnonymous(String token,
          {required int conversationId,
          required String body,
          required String clientId,
          int? replyToId,
          String? gifId}) async =>
      backend.sendAnonymousMessage(
          backendUrl: await _url(),
          token: token,
          conversationId: conversationId,
          body: body,
          clientId: clientId,
          replyToId: replyToId,
          gifId: gifId);

  Future<AnonymousProfile> fetchAnonymousProfile(
          String token, int conversationId) async =>
      backend.fetchAnonymousProfile(
          backendUrl: await _url(),
          token: token,
          conversationId: conversationId);

  Future<AnonymousProfile> requestReveal(
          String token, int conversationId) async =>
      backend.requestReveal(
          backendUrl: await _url(),
          token: token,
          conversationId: conversationId);

  Future<RevealAnswer> answerReveal(
          String token, int conversationId, bool accept) async =>
      backend.answerReveal(
          backendUrl: await _url(),
          token: token,
          conversationId: conversationId,
          accept: accept);

  Future<void> reportAnonymous(String token, int conversationId,
          {required String reason, String? details}) async =>
      backend.reportAnonymous(
          backendUrl: await _url(),
          token: token,
          conversationId: conversationId,
          reason: reason,
          details: details);

  Future<bool> setAnonymousMessaging(String token, bool enabled) async =>
      backend.setAnonymousMessaging(
          backendUrl: await _url(), token: token, enabled: enabled);

  /// The conversation's id with this person (created on first use).
  /// Where Message on their profile goes: our direct conversation, or my
  /// anonymous one with them (started the first time).
  Future<MessageTarget> startConversation(String token, int userId) async =>
      backend.startConversation(
          backendUrl: await _url(), token: token, userId: userId);

  // ---- unmatching ----

  Future<List<UnmatchedPerson>> fetchUnmatches(String token) async =>
      backend.fetchMyUnmatches(backendUrl: await _url(), token: token);

  Future<void> unmatch(String token, int userId) async => backend.unmatchUser(
      backendUrl: await _url(), token: token, userId: userId);

  Future<void> removeUnmatch(String token, int userId) async => backend
      .removeUnmatch(backendUrl: await _url(), token: token, userId: userId);

  Future<Profile> fetchUnmatchedProfile(String token, int userId) async =>
      backend.fetchUnmatchedProfile(
          backendUrl: await _url(), token: token, userId: userId);

  Future<void> setAnonymousUnmatch(
          String token, int conversationId, bool unmatched) async =>
      backend.setAnonymousUnmatch(
          backendUrl: await _url(),
          token: token,
          conversationId: conversationId,
          unmatched: unmatched);

  Future<MessagePage> fetchMessages(String token, int conversationId,
          {int? before, int? after}) async =>
      backend.fetchMessages(
          backendUrl: await _url(),
          token: token,
          conversationId: conversationId,
          before: before,
          after: after);

  Future<ChatMessage> send(String token,
          {required int recipientId,
          required String body,
          required String clientId,
          int? replyToId,
          String? gifId}) async =>
      backend.sendMessage(
          backendUrl: await _url(),
          token: token,
          recipientId: recipientId,
          body: body,
          clientId: clientId,
          replyToId: replyToId,
          gifId: gifId);

  /// GIFs or stickers for the GIF picker (trending when [query] is empty).
  Future<GifPage> fetchGifs(String token,
          {required bool stickers, String query = '', int offset = 0}) async =>
      backend.fetchGifs(
          backendUrl: await _url(),
          token: token,
          stickers: stickers,
          query: query,
          offset: offset);

  Future<void> markRead(String token, int conversationId) async =>
      backend.markConversationRead(
          backendUrl: await _url(),
          token: token,
          conversationId: conversationId);

  Future<ChatMessage> fetchMessage(String token, int messageId) async =>
      backend.fetchMessage(
          backendUrl: await _url(), token: token, messageId: messageId);

  /// A photo or video (processed by the backend), saved once per [clientId].
  Future<ChatMessage> sendMedia(String token,
          {required int recipientId,
          required List<int> bytes,
          required String filename,
          required String clientId,
          int? replyToId,
          void Function(double sent)? onProgress}) async =>
      backend.sendChatMedia(
          backendUrl: await _url(),
          token: token,
          recipientId: recipientId,
          bytes: bytes,
          filename: filename,
          clientId: clientId,
          replyToId: replyToId,
          onProgress: onProgress);

  /// Access to the actual photo or video (starts the recipient's countdown).
  Future<MediaAccess> openMedia(String token, int attachmentId) async =>
      backend.openChatMedia(
          backendUrl: await _url(), token: token, attachmentId: attachmentId);

  Future<ChatMessage> offerAlbum(String token,
          {required int recipientId,
          required int albumId,
          required String clientId,
          int? replyToId}) async =>
      backend.offerAlbum(
          backendUrl: await _url(),
          token: token,
          recipientId: recipientId,
          albumId: albumId,
          clientId: clientId,
          replyToId: replyToId);

  Future<ChatMessage> respondToTrade(
          String token, int tradeId, int albumId) async =>
      backend.respondToTrade(
          backendUrl: await _url(),
          token: token,
          tradeId: tradeId,
          albumId: albumId);

  Future<ChatMessage> cancelTrade(String token, int tradeId) async => backend
      .cancelTrade(backendUrl: await _url(), token: token, tradeId: tradeId);

  /// The other person's album of a completed trade (starts my countdown).
  Future<TradedAlbumAccess> viewTradedAlbum(String token, int tradeId) async =>
      backend.viewTradedAlbum(
          backendUrl: await _url(), token: token, tradeId: tradeId);

  Future<void> viewHeartbeat(String token, String viewToken) async =>
      backend.mediaViewHeartbeat(
          backendUrl: await _url(), token: token, viewToken: viewToken);

  Future<void> endView(String token, String viewToken) async =>
      backend.endMediaView(
          backendUrl: await _url(), token: token, viewToken: viewToken);

  Future<void> typing(String token, int conversationId, bool active) async =>
      backend.sendTyping(
          backendUrl: await _url(),
          token: token,
          conversationId: conversationId,
          active: active);

  /// Where I am now, once.
  Future<ChatMessage> shareLocation(String token,
          {required int recipientId,
          required String clientId,
          required double latitude,
          required double longitude,
          double? accuracy,
          int? replyToId}) async =>
      backend.shareLocation(
          backendUrl: await _url(),
          token: token,
          recipientId: recipientId,
          clientId: clientId,
          latitude: latitude,
          longitude: longitude,
          accuracy: accuracy,
          replyToId: replyToId);

  /// My reaction on a message (null removes it).
  Future<ChatMessage> react(String token, int messageId, String? emoji) async =>
      backend.reactToMessage(
          backendUrl: await _url(),
          token: token,
          messageId: messageId,
          emoji: emoji);

  Future<ChatMessage> requestLiveLocation(String token,
          {required int recipientId,
          required String clientId,
          int? replyToId}) async =>
      backend.requestLiveLocation(
          backendUrl: await _url(),
          token: token,
          recipientId: recipientId,
          clientId: clientId,
          replyToId: replyToId);

  Future<ChatMessage> liveLocationAction(
          String token, int messageId, String action, {String? reason}) async =>
      backend.liveLocationAction(
          backendUrl: await _url(),
          token: token,
          messageId: messageId,
          action: action,
          reason: reason);

  Future<void> sendLivePosition(String token, int messageId,
          {required double latitude,
          required double longitude,
          double? accuracy}) async =>
      backend.sendLivePosition(
          backendUrl: await _url(),
          token: token,
          messageId: messageId,
          latitude: latitude,
          longitude: longitude,
          accuracy: accuracy);

  Future<void> liveHeartbeat(String token, int messageId) async =>
      backend.liveLocationHeartbeat(
          backendUrl: await _url(), token: token, messageId: messageId);

  Future<LivePositions> fetchLivePositions(String token, int messageId) async =>
      backend.fetchLivePositions(
          backendUrl: await _url(), token: token, messageId: messageId);

  Future<ChatMessage> stopSharingLocation(String token, int messageId) async =>
      backend.stopSharingLocation(
          backendUrl: await _url(), token: token, messageId: messageId);
}
