import 'dart:async';

import 'package:flutter/material.dart';

import '../services/guest_chat_api.dart';
import '../state/guest_chats_state.dart';
import '../state/messaging_state.dart';
import '../theme.dart';
import '../widgets/chat/anonymous_chat.dart' show AnonymousClosedBar;
import '../widgets/chat/guest_chat_view.dart';
import 'chat_screen.dart';

/// A guest chat, as its host sees it (someone not on HUNTR, from my guest
/// link): the shared guest chat view, with End chat and Block in the menu.
class GuestChatScreen extends StatefulWidget {
  const GuestChatScreen({super.key, required this.chat});

  final GuestChatSummary chat;

  @override
  State<GuestChatScreen> createState() => _GuestChatScreenState();
}

class _GuestChatScreenState extends State<GuestChatScreen> {
  GuestChatsState? _state;
  GuestChatController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final state = GuestChatsScope.read(context);
    if (state == null) return;
    _state = state;
    // GIFs and stickers: my usual GIF search
    final controller = state.open(widget.chat.id,
        gifs: MessagingScope.read(context)?.gifs)
      ..chat = widget.chat;
    _controller = controller;
    unawaited(controller.start());
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      _state?.close(widget.chat.id, controller);
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _menu(String choice) async {
    final state = _state;
    if (state == null) return;
    final block = choice == 'block';
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(block ? 'Block this guest?' : 'End this chat?'),
        content: Text(block
            ? 'The chat ends and is deleted, and they can’t start another one '
                'with you for a day.'
            : 'The chat ends and is deleted for both of you.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              key: const Key('guestChatConfirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(block ? 'Block' : 'End chat')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    block ? await state.block(widget.chat.id) : await state.end(widget.chat.id);
    if (mounted) Navigator.of(context).pop();
  }

  /// The guest joined HUNTR: our chat moved to my anonymous chats.
  Future<void> _openMoved(int conversationId) async {
    final messaging = MessagingScope.read(context);
    if (messaging == null) return;
    await messaging.refresh();
    if (!mounted) return;
    final summary = messaging.summary(conversationId);
    if (summary == null) return;
    await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ChatScreen.conversation(
            conversationId: conversationId, other: summary.other)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const Scaffold();
    final chat = widget.chat;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final moved = controller.joinedConversationId;
        return GuestChatView(
          controller: controller,
          guestTag: true,
          intro: GuestChatIntro(
            animal: chat.avatar,
            title: '${chat.name} opened your guest link',
            text: 'They’re not on HUNTR. The chat ends '
                '${chat.idleMinutes} minutes after their last message, and '
                'your replies don’t extend it.',
          ),
          actions: [
            PopupMenuButton<String>(
              key: const Key('guestChatMenu'),
              tooltip: 'More',
              onSelected: _menu,
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'end',
                    child: Row(children: [
                      Icon(Icons.close_rounded),
                      SizedBox(width: 12),
                      Text('End chat'),
                    ])),
                const PopupMenuItem(
                    key: Key('blockGuest'),
                    value: 'block',
                    child: Row(children: [
                      Icon(Icons.block_rounded, color: Color(0xFFFF8A80)),
                      SizedBox(width: 12),
                      Text('Block guest',
                          style: TextStyle(color: Color(0xFFFF8A80))),
                    ])),
              ],
            ),
          ],
          ended: moved == null
              ? const AnonymousClosedBar(
                  message: 'This chat has ended and was deleted.')
              : SafeArea(
                  top: false,
                  child: Container(
                    key: const Key('guestJoinedBar'),
                    margin: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                    padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                    decoration: BoxDecoration(
                      color: HuntrColors.orange.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: HuntrColors.orange.withValues(alpha: 0.4)),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                            '${chat.name} joined HUNTR. Your chat continues '
                            'in Anonymous, and no longer expires.',
                            style: const TextStyle(height: 1.4)),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: () => _openMoved(moved),
                        child: const Text('Open chat'),
                      ),
                    ]),
                  ),
                ),
        );
      },
    );
  }
}
