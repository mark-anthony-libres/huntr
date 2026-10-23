import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Lets a swipeable view (PageView) be dragged with a mouse or trackpad too;
/// Flutter only allows touch by default.
class SwipeAnyDevice extends StatelessWidget {
  const SwipeAnyDevice({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      }),
      child: child,
    );
  }
}

/// Which page of a swipeable viewer is shown.
class PageDots extends StatelessWidget {
  const PageDots({super.key, required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: i == current ? 18 : 7,
            height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: i == current
                  ? HuntrColors.orange
                  : Colors.white.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

/// Previous/next for mouse users (a mouse can also drag, see
/// [SwipeAnyDevice]).
class ArrowButton extends StatelessWidget {
  const ArrowButton(
      {super.key,
      required this.icon,
      required this.tooltip,
      required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          icon: Icon(icon, color: Colors.white, size: 30),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
