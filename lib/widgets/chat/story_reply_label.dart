import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../theme.dart';

/// Over a story reply's bubble, on its side of the chat: "You replied to
/// Sam's story" / "Replied to your story", or "reacted" when it's just an
/// emoji (a quick reaction). Other messages are shown as they are.
class StoryReplyLabel extends StatelessWidget {
  const StoryReplyLabel(
      {super.key,
      required this.fromMe,
      required this.otherName,
      required this.reaction});

  final bool fromMe;

  /// The other person's name (empty: "their").
  final String otherName;

  /// Only an emoji (a quick reaction), not a written reply.
  final bool reaction;

  /// [bubble], with the label over it when [message] is a story reply.
  static Widget over(ChatMessage message, Widget bubble,
          {required String otherName}) =>
      message.type != ChatMessageType.storyReply
          ? bubble
          : Column(
              crossAxisAlignment: message.fromMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                StoryReplyLabel(
                    fromMe: message.fromMe,
                    otherName: otherName,
                    reaction: isReaction(message.body)),
                bubble,
              ],
            );

  /// Just emoji: no letters, digits or spaces, and short.
  static bool isReaction(String body) =>
      RegExp(r'^[^\p{L}\p{N}\s]{1,8}$', unicode: true).hasMatch(body.trim());

  @override
  Widget build(BuildContext context) {
    final verb = reaction ? 'reacted to' : 'replied to';
    final whose = otherName.trim().isEmpty ? 'their' : "${otherName.trim()}'s";
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.auto_stories_outlined,
            size: 14, color: HuntrColors.orange),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            fromMe
                ? 'You $verb $whose story'
                : '${reaction ? 'Reacted' : 'Replied'} to your story',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: HuntrColors.muted, fontSize: 12),
          ),
        ),
      ]),
    );
  }
}
