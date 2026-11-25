import 'package:flutter/material.dart';

import '../../theme.dart';

/// A chat list row's frame: a warm tint and edge while unread, outlined
/// while open beside the list (wide screens). Chats and guest chats share
/// it.
class ChatRowFrame extends StatelessWidget {
  const ChatRowFrame({
    super.key,
    required this.unread,
    required this.onTap,
    required this.child,
    this.selected = false,
    this.onLongPress,
    this.inkKey,
  });

  final bool unread;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// The tappable part's key (tests find a row by it).
  final Key? inkKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Material(
          color: selected
              ? HuntrColors.surfaceHigh
              : unread
                  ? HuntrColors.orange.withValues(alpha: 0.07)
                  : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
                color: selected
                    ? HuntrColors.orange.withValues(alpha: 0.5)
                    : unread
                        ? HuntrColors.orange.withValues(alpha: 0.22)
                        : Colors.transparent),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: inkKey,
            onTap: onTap,
            onLongPress: onLongPress,
            hoverColor: HuntrColors.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
              child: child,
            ),
          ),
        ),
      );
}

/// How many unread messages a chat has, as a pill.
class UnreadCountPill extends StatelessWidget {
  const UnreadCountPill({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 22),
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
            gradient: HuntrColors.accentGradient,
            borderRadius: const BorderRadius.all(Radius.circular(11))),
        child: Text(count > 99 ? '99+' : '$count',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.black)),
      );
}
