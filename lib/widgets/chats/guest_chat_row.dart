import 'package:flutter/material.dart';

import '../../services/guest_chat_api.dart';
import '../../theme.dart';
import '../anonymous_avatar.dart';
import '../chat/guest_chat_view.dart' show GuestTag;
import 'chat_row_frame.dart';

/// A guest chat in my Anonymous chats: like an anonymous chat's row (their
/// animal and anonymous name, the last message, unread), with a GUEST tag
/// and the minutes it has left.
class GuestChatRow extends StatelessWidget {
  const GuestChatRow(
      {super.key, required this.chat, required this.now, required this.onTap});

  final GuestChatSummary chat;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = chat.unread > 0;
    final last = chat.lastMessage;
    final left = chat.minutesLeft(now);
    return ChatRowFrame(
      unread: unread,
      inkKey: Key('guestChat-${chat.id}'),
      onTap: onTap,
      child: Row(children: [
        SizedBox.square(
          dimension: 56,
          child: AnonymousArt(animal: chat.avatar, radius: 28, size: 56),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                // the name and the tag get the room; the time at the end
                Expanded(
                  child: Row(children: [
                    Flexible(
                      child: Text(chat.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                              fontWeight:
                                  unread ? FontWeight.w800 : FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    const GuestTag(),
                  ]),
                ),
                const SizedBox(width: 8),
                Text(chat.ended ? 'Ended' : '${left}m left',
                    key: Key('guestTimeLeft-${chat.id}'),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: !chat.ended && left <= 2
                            ? HuntrColors.orange
                            : HuntrColors.muted)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: Text(
                    last == null
                        ? 'Opened your guest link'
                        : '${last.mine ? 'You: ' : ''}${last.preview}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        color: unread ? Colors.white : HuntrColors.muted,
                        fontWeight: unread ? FontWeight.w600 : FontWeight.w400),
                  ),
                ),
                if (unread) ...[
                  const SizedBox(width: 10),
                  UnreadCountPill(
                      key: Key('guestUnread-${chat.id}'), count: chat.unread),
                ],
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}
