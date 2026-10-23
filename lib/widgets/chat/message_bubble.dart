import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../theme.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble(
      {super.key,
      required this.message,
      required this.tail,
      required this.showStatus});
  final Message message;
  final bool tail;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final me = message.fromMe;
    final r = const Radius.circular(20);
    final small = const Radius.circular(6);
    final isEmojiOnly = message.text.runes.length <= 2 &&
        !RegExp(r'[A-Za-z0-9]').hasMatch(message.text);
    return Align(
      // only as wide as the bubble when there's room (e.g. beside the
      // reaction button); a full-width row still puts it on its side
      widthFactor: 1,
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            me ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: EdgeInsets.only(top: 2, bottom: tail ? 6 : 1),
            constraints: BoxConstraints(
                // three quarters of a phone; at most 520 on wide screens
                maxWidth:
                    math.min(MediaQuery.sizeOf(context).width * 0.74, 520)),
            padding: isEmojiOnly
                ? const EdgeInsets.all(4)
                : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: isEmojiOnly
                ? null
                : BoxDecoration(
                    gradient: me ? HuntrColors.accentGradient : null,
                    color: me ? null : HuntrColors.surfaceHigh,
                    borderRadius: BorderRadius.only(
                      topLeft: r,
                      topRight: r,
                      bottomLeft: me || !tail ? r : small,
                      bottomRight: me && tail ? small : r,
                    ),
                  ),
            child: Text(
              message.text,
              style: TextStyle(
                fontSize: isEmojiOnly ? 40 : 15.5,
                height: 1.3,
                color: me ? Colors.black : Colors.white,
                fontWeight: me ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
          if (showStatus) MessageStatusLine(status: message.status),
        ],
      ),
    );
  }
}

/// Under my message: Sending… / Sent / Read / Not sent · Tap to retry.
class MessageStatusLine extends StatelessWidget {
  const MessageStatusLine({super.key, required this.status, this.detail});

  final MessageStatus status;

  /// Why it wasn't sent, when known (e.g. "The video is too long…").
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (status) {
      MessageStatus.read => (
          Icons.done_all_rounded,
          'Read',
          HuntrColors.orange
        ),
      MessageStatus.sending => (
          Icons.schedule_rounded,
          'Sending…',
          HuntrColors.muted
        ),
      MessageStatus.failed => (
          Icons.error_outline_rounded,
          'Not sent · Tap to retry',
          HuntrColors.coral
        ),
      MessageStatus.sent => (Icons.done_rounded, 'Sent', HuntrColors.muted),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, right: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ]),
        if (detail != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(detail!,
                key: const Key('sendError'),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12, color: color)),
          ),
      ]),
    );
  }
}
