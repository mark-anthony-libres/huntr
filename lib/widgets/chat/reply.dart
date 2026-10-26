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
    final accent = quote.fromMe ? HuntrColors.orange : HuntrColors.active;
    // Who replied to whom, on its own quiet line; then the quoted message
    // in a soft card of its own, apart from the reply's bubble.
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.reply_rounded,
                  size: 14, color: HuntrColors.muted),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                    mine
                        ? 'You replied to ${quote.fromMe ? 'yourself' : who}'
                        : '$otherName replied to ${quote.fromMe ? 'you' : 'themselves'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: HuntrColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          MouseRegion(
            cursor:
                onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
            child: GestureDetector(
              key: Key('replyQuote-${quote.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 16, 11),
                decoration: BoxDecoration(
                  color: HuntrColors.surfaceHigh.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(quote.text,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.62),
                                fontSize: 14,
                                height: 1.4)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
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
