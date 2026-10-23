import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../theme.dart';

/// On a reply, above it: whose message it answers and what it said (2 lines
/// at most). Tapping it goes to that message.
class ReplyQuote extends StatelessWidget {
  const ReplyQuote(
      {super.key,
      required this.quote,
      required this.otherName,
      required this.mine,
      this.onTap});

  final ReplyPreview quote;

  /// The other person's name (when the quoted message is theirs).
  final String otherName;

  /// The reply is mine (it sits on my side).
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final who = quote.fromMe ? 'You' : otherName;
    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        key: Key('replyQuote-${quote.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(top: 4, bottom: 2),
          padding: const EdgeInsets.fromLTRB(10, 6, 12, 8),
          decoration: BoxDecoration(
            color: HuntrColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border(
              left: BorderSide(
                  color: quote.fromMe ? HuntrColors.orange : HuntrColors.active,
                  width: 3),
            ),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.reply_rounded,
                      size: 14, color: HuntrColors.muted),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                        mine
                            ? 'You replied to ${quote.fromMe ? 'yourself' : who}'
                            : '$otherName replied to ${quote.fromMe ? 'you' : 'themselves'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: HuntrColors.muted, fontSize: 11.5)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(quote.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13.5, height: 1.3)),
              ]),
        ),
      ),
    );
  }
}

/// Above the message box while replying: to whom and what, and ✕ to stop.
class ReplyBanner extends StatelessWidget {
  const ReplyBanner(
      {super.key,
      required this.message,
      required this.otherName,
      required this.onCancel});

  final ChatMessage message;
  final String otherName;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final quote = ReplyPreview.of(message);
    return Container(
      key: const Key('replyBanner'),
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: HuntrColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(
              color: message.fromMe ? HuntrColors.orange : HuntrColors.active,
              width: 3),
        ),
      ),
      child: Row(children: [
        const Icon(Icons.reply_rounded, size: 20, color: HuntrColors.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Replying to ${message.fromMe ? 'yourself' : otherName}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 2),
                Text(quote.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: HuntrColors.muted, fontSize: 13)),
              ]),
        ),
        IconButton(
          key: const Key('cancelReply'),
          tooltip: 'Cancel reply',
          icon: const Icon(Icons.close_rounded),
          onPressed: onCancel,
        ),
      ]),
    );
  }
}
