import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../theme.dart';

/// Over a story reply's bubble, on its side of the chat: "You replied to
/// Sam's story" / "Replied to your story", or "reacted" when it's just an
/// emoji (a quick reaction), and under that the story while it's still up
/// (tap: watch it), or "Story unavailable" once it's gone. Other messages
/// are shown as they are.
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

  /// [bubble], with the label (and the story) over it when [message] is a
  /// story reply. [onOpenStory] plays that story.
  static Widget over(ChatMessage message, Widget bubble,
          {required String otherName, VoidCallback? onOpenStory}) =>
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
                if (message.storyId != null)
                  StoryReplyPreview(message: message, onOpen: onOpenStory),
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
        Icon(Icons.auto_stories_outlined, size: 14, color: HuntrColors.orange),
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

/// The story a reply answered, as Instagram shows it: a small portrait
/// thumbnail to tap and watch while it's still up; "Story unavailable" once
/// it has expired or been deleted.
class StoryReplyPreview extends StatelessWidget {
  const StoryReplyPreview({super.key, required this.message, this.onOpen});

  final ChatMessage message;
  final VoidCallback? onOpen;

  static const _width = 96.0;
  static const _height = 160.0;

  @override
  Widget build(BuildContext context) {
    final url = message.storyThumbnailUrl;
    if (!message.storyAvailable) {
      return Padding(
        key: Key('storyReplyGone-${message.id}'),
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: HuntrColors.border),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.history_toggle_off_rounded,
                size: 15, color: HuntrColors.muted),
            SizedBox(width: 6),
            Text('Story unavailable',
                style: TextStyle(color: HuntrColors.muted, fontSize: 12.5)),
          ]),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      child: Material(
        color: HuntrColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('storyReplyPreview-${message.id}'),
          onTap: onOpen,
          child: SizedBox(
            width: _width,
            height: _height,
            child: Stack(fit: StackFit.expand, children: [
              if (url != null)
                Image.network(url,
                    fit: BoxFit.cover,
                    // a plain <img> on web: no CORS needed for the bucket
                    webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                    errorBuilder: (context, error, stack) =>
                        const SizedBox.shrink()),
              // a play mark: it's a video
              const Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: Color(0x80000000)),
                  child: Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 22),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
