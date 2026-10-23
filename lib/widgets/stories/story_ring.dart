import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';

/// The ring around someone who has a story: HUNTR's orange gradient while
/// there's something I haven't watched (slowly turning, with a soft glow,
/// when [animate]), plain grey once I've seen it all.
class StoryRing extends StatefulWidget {
  const StoryRing({
    super.key,
    required this.seen,
    required this.child,
    this.circle = false,
    this.radius = 18,
    this.width = 2.5,
    this.animate = false,
  });

  final bool seen;
  final Widget child;

  /// Round (an avatar) rather than a rounded card.
  final bool circle;

  /// The corner radius of the [child] (cards only).
  final double radius;
  final double width;

  /// Turn the gradient (only while unseen, and not when the device asks for
  /// less motion).
  final bool animate;

  @override
  State<StoryRing> createState() => _StoryRingState();
}

class _StoryRingState extends State<StoryRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn =
      AnimationController(vsync: this, duration: const Duration(seconds: 3));

  static const _colors = [
    HuntrColors.orange,
    HuntrColors.ember,
    HuntrColors.coral,
    Color(0xFFFFC14D),
    HuntrColors.orange,
  ];

  bool get _moving =>
      widget.animate &&
      !widget.seen &&
      !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(StoryRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (_moving && !_turn.isAnimating) {
      _turn.repeat();
    } else if (!_moving && _turn.isAnimating) {
      _turn.stop();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  BoxDecoration _decoration(double turns) => BoxDecoration(
        gradient: widget.seen
            ? null
            : SweepGradient(
                colors: _colors,
                transform: GradientRotation(turns * 2 * math.pi)),
        color: widget.seen ? HuntrColors.muted.withValues(alpha: 0.45) : null,
        shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: widget.circle
            ? null
            : BorderRadius.circular(widget.radius + widget.width),
        boxShadow: widget.seen || !widget.animate
            ? null
            : [
                BoxShadow(
                    color: HuntrColors.ember.withValues(alpha: 0.35),
                    blurRadius: 14,
                    spreadRadius: 1),
              ],
      );

  @override
  Widget build(BuildContext context) {
    final child =
        Padding(padding: EdgeInsets.all(widget.width), child: widget.child);
    if (!_moving) {
      return DecoratedBox(decoration: _decoration(0), child: child);
    }
    return AnimatedBuilder(
      animation: _turn,
      child: child,
      builder: (_, child) =>
          DecoratedBox(decoration: _decoration(_turn.value), child: child),
    );
  }
}
