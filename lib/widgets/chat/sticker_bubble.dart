import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../theme.dart';
import 'sticker_image.dart';

/// One of HUNTR's stickers in the chat: the sticker itself, no bubble. My
/// own, while it still counts on their profile, can be undone ([onUndo]):
/// tapping it asks first.
class StickerBubble extends StatelessWidget {
  const StickerBubble({super.key, required this.message, this.onUndo});

  final ChatMessage message;

  /// Takes it back (only on my own sticker that still counts).
  final Future<void> Function()? onUndo;

  static const size = 132.0;

  Future<void> _askUndo(BuildContext context) async {
    final name = message.sticker?.name ?? 'sticker';
    final undo = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            StickerImage(url: message.sticker?.imageUrl, name: name, size: 96),
            const SizedBox(height: 10),
            Text('Undo “$name”?',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text(
                "It leaves the chat and stops counting on their profile. "
                'You can send it again later.',
                textAlign: TextAlign.center,
                style: TextStyle(color: HuntrColors.muted, height: 1.4)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('undoStickerConfirm'),
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Undo sticker'),
                onPressed: () => Navigator.of(sheetContext).pop(true),
              ),
            ),
          ]),
        ),
      ),
    );
    if (undo == true) await onUndo?.call();
  }

  @override
  Widget build(BuildContext context) {
    final sticker = message.sticker;
    if (sticker == null) return const SizedBox.shrink();
    final canUndo =
        onUndo != null && message.fromMe && sticker.active && !message.pending;
    final picture = StickerImage(
      key: Key('sticker-${message.id ?? message.clientId}'),
      url: sticker.imageUrl,
      name: sticker.name,
      size: size,
    );
    return Column(
      crossAxisAlignment:
          message.fromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: message.pending ? 0.6 : 1,
          // just the sticker: no hover box or tooltip over it
          child: canUndo
              ? Semantics(
                  button: true,
                  hint: 'Tap to undo',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _askUndo(context),
                      child: picture,
                    ),
                  ),
                )
              : picture,
        ),
        // ended by a block: it stays in the history, but doesn't count
        if (!sticker.active && !message.pending)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text('No longer counts',
                style: TextStyle(color: HuntrColors.muted, fontSize: 11)),
          ),
      ],
    );
  }
}
