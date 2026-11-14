import 'package:flutter/material.dart';

import '../theme.dart';

/// The sensitive-content warning, in place of something that may be NSFW
/// (for someone whose Don't show NSFW content is on): [background] under a
/// gradient veil, "Sensitive content", [message], and [actionLabel] (View album,
/// View Image, Play Video) - plus Cancel when [onCancel] is given. Nothing
/// behind it is shown or played until [onView].
///
/// Full screen for albums; [compact] for a Threads post's photo or video in
/// the feed (smaller, the button only as wide as its label).
class SensitiveContentCover extends StatelessWidget {
  const SensitiveContentCover({
    super.key,
    this.background,
    required this.message,
    required this.actionLabel,
    this.actionIcon,
    required this.onView,
    this.onCancel,
    this.compact = false,
  });

  /// What it hides, already blurred (none: black).
  final Widget? background;
  final String message;
  final String actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onView;
  final VoidCallback? onCancel;
  final bool compact;

  /// An album's warning: its blurred preview (the one on the chat card).
  static Widget album(
          {Key? key,
          String? coverUrl,
          required VoidCallback onView,
          required VoidCallback onCancel}) =>
      SensitiveContentCover(
        key: key ?? const Key('sensitiveAlbum'),
        background: coverUrl == null
            ? null
            : Image.network(coverUrl,
                fit: BoxFit.cover,
                webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                errorBuilder: (context, error, stack) =>
                    const SizedBox.shrink()),
        message: 'This album may contain nudity or sexually explicit content.',
        actionLabel: 'View album',
        onView: onView,
        onCancel: onCancel,
      );

  @override
  Widget build(BuildContext context) {
    final icon = compact ? 22.0 : 30.0;
    final circle = compact ? 46.0 : 64.0;
    final view = FilledButton(
      key: const Key('sensitiveView'),
      style: FilledButton.styleFrom(
          backgroundColor: HuntrColors.orange,
          foregroundColor: Colors.black,
          minimumSize: compact ? const Size(0, 40) : const Size.fromHeight(48)),
      onPressed: onView,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (actionIcon != null) ...[
          Icon(actionIcon, size: compact ? 20 : 22),
          const SizedBox(width: 6),
        ],
        Text(actionLabel,
            style: TextStyle(
                fontSize: compact ? 14.5 : 16, fontWeight: FontWeight.w700)),
      ]),
    );
    return Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: Colors.black),
      if (background != null) background!,
      // a veil: a touch of the accent at the top, darker towards the bottom
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              HuntrColors.orange.withValues(alpha: 0.28),
              Colors.black.withValues(alpha: 0.55),
              Colors.black.withValues(alpha: 0.85),
            ],
          ),
        ),
      ),
      Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 14 : 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: circle,
                height: circle,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.5),
                  border: Border.all(color: Colors.white24),
                ),
                child: Icon(Icons.visibility_off_outlined,
                    color: Colors.white, size: icon),
              ),
              SizedBox(height: compact ? 10 : 18),
              Text('Sensitive content',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 16.5 : 20,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: compact ? 4 : 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: compact ? 13.5 : 15,
                    height: 1.4),
              ),
              SizedBox(height: compact ? 14 : 24),
              if (compact)
                view
              else
                SizedBox(width: double.infinity, child: view),
              if (onCancel != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    key: const Key('sensitiveCancel'),
                    style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48)),
                    onPressed: onCancel,
                    child:
                        const Text('Cancel', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    ]);
  }
}
