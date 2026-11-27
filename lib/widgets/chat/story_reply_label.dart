import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../theme.dart';

/// Over a story reply's bubble, on its side of the chat: "You replied to
/// Sam's story" / "Replied to your story", or "reacted" when it's just an
/// emoji (a quick reaction), and under that the story while it's still up
/// (tap: watch it), or "Story unavailable" once it's gone. A photo reply
/// the same, with the profile photo ("Photo unavailable" once it's off
/// their profile). Other messages are shown as they are.
class StoryReplyLabel extends StatelessWidget {
  const StoryReplyLabel(
      {super.key,
      required this.fromMe,
      required this.otherName,
      required this.reaction,
      this.photo = false,
      this.bio = false});

  final bool fromMe;

  /// A reply to a profile photo, not a story.
  final bool photo;

  /// A reply to a bio, not a story.
  final bool bio;

  /// The other person's name (empty: "their").
  final String otherName;

  /// Only an emoji (a quick reaction), not a written reply.
  final bool reaction;

  /// [bubble], with the label (and the story) over it when [message] is a
  /// story reply. [onOpenStory] plays that story.
  static Widget over(ChatMessage message, Widget bubble,
          {required String otherName, VoidCallback? onOpenStory}) =>
      message.type != ChatMessageType.storyReply &&
              message.type != ChatMessageType.photoReply &&
              message.type != ChatMessageType.bioReply
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
                    reaction: isReaction(message.body),
                    photo: message.type == ChatMessageType.photoReply,
                    bio: message.type == ChatMessageType.bioReply),
                if (message.type == ChatMessageType.photoReply)
                  PhotoReplyPreview(message: message)
                else if (message.type == ChatMessageType.bioReply)
                  BioReplyQuote(message: message)
                else if (message.storyId != null)
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
    final whose = otherName.trim().isEmpty ? 'a' : "${otherName.trim()}'s";
    final what = bio
        ? 'bio'
        : photo
            ? 'photo'
            : 'story';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
            bio
                ? Icons.format_quote_rounded
                : photo
                    ? Icons.photo_outlined
                    : Icons.auto_stories_outlined,
            size: 14,
            color: HuntrColors.orange),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            fromMe
                ? 'You $verb $whose $what'
                : '${reaction ? 'Reacted' : 'Replied'} to your $what',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: HuntrColors.muted, fontSize: 12),
          ),
        ),
      ]),
    );
  }
}

/// The bio a reply answered, as it was then: a quote over the reply.
class BioReplyQuote extends StatelessWidget {
  const BioReplyQuote({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final bio = message.bioQuote?.trim() ?? '';
    return Padding(
      key: Key('bioReplyQuote-${message.id}'),
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: HuntrColors.surface,
            borderRadius: BorderRadius.circular(12),
            border:
                Border(left: BorderSide(color: HuntrColors.orange, width: 3)),
          ),
          child: Text(bio.isEmpty ? 'Bio unavailable' : bio,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: HuntrColors.muted, fontSize: 13, height: 1.35)),
        ),
      ),
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

/// The profile photo a reply answered: a small copy while it's still on
/// their profile; "Photo unavailable" once it's gone.
class PhotoReplyPreview extends StatelessWidget {
  const PhotoReplyPreview({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final url = message.photoThumbnailUrl;
    if (!message.photoAvailable) {
      return Padding(
        key: Key('photoReplyGone-${message.id}'),
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: HuntrColors.border),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.hide_image_outlined, size: 15, color: HuntrColors.muted),
            SizedBox(width: 6),
            Text('Photo unavailable',
                style: TextStyle(color: HuntrColors.muted, fontSize: 12.5)),
          ]),
        ),
      );
    }
    return Padding(
      key: Key('photoReplyPreview-${message.id}'),
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 96,
          height: 120,
          color: HuntrColors.surfaceHigh,
          child: url == null
              ? null
              : Image.network(url,
                  fit: BoxFit.cover,
                  // a plain <img> on web: no CORS needed for the bucket
                  webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                  errorBuilder: (context, error, stack) =>
                      const SizedBox.shrink()),
        ),
      ),
    );
  }
}
