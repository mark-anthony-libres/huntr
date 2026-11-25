import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../screens/chat_screen.dart';
import '../services/guest_chat_api.dart';
import '../services/huntr_backend.dart' show BackendException;
import '../state/app_state.dart';
import '../state/messaging_state.dart';

/// The guest side's memory on this device: each link's chat secret (so a
/// reload keeps the chat), and a chat to move into HUNTR after signing in.
class GuestStore {
  GuestStore._();

  static const _storage = FlutterSecureStorage();
  static const _joinKey = 'huntr_guest_join';

  static String _chatKey(String code) => 'huntr_guest_chat_$code';

  static Future<String?> token(String code) async {
    try {
      return await _storage.read(key: _chatKey(code));
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveToken(String code, String token) async {
    try {
      await _storage.write(key: _chatKey(code), value: token);
    } catch (_) {}
  }

  static Future<void> forget(String code) async {
    try {
      await _storage.delete(key: _chatKey(code));
    } catch (_) {}
  }

  /// The chat to move into HUNTR once signed in.
  static Future<void> saveJoin(String token) async {
    try {
      await _storage.write(key: _joinKey, value: token);
    } catch (_) {}
  }

  static Future<String?> takeJoin() async {
    try {
      final token = await _storage.read(key: _joinKey);
      if (token != null) await _storage.delete(key: _joinKey);
      return token;
    } catch (_) {
      return null;
    }
  }
}

/// Signed in after "Join HUNTR to keep talking": the guest chat moves into
/// our mutual anonymous chat (still anonymous, both of us), which opens.
Future<void> completeGuestJoin(BuildContext context,
    {String? guestToken, GuestChatApi? api}) async {
  final token = guestToken ?? await GuestStore.takeJoin();
  if (token == null || !context.mounted) return;
  final session = AppScope.read(context).sessionToken;
  final messaging = MessagingScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  if (session == null) return;
  try {
    final conversationId = await (api ?? GuestChatApi()).join(session, token);
    await messaging?.refresh();
    final summary = messaging?.summary(conversationId);
    if (summary == null) return;
    await navigator.push(MaterialPageRoute(
        builder: (_) => ChatScreen.conversation(
            conversationId: conversationId, other: summary.other)));
  } on GuestChatEndedException {
    messenger.showSnackBar(const SnackBar(
        content: Text('That chat had already ended, so it couldn’t move to '
            'your account.')));
  } on BackendException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Your guest chat couldn’t move to your account.')));
  }
}
