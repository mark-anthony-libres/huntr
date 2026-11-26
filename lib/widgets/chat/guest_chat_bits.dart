import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';

// Pieces a guest chat (an anonymous chat from a guest link) shows in the
// chat screen and the chat list.

/// "GUEST": a guest chat's guest (not on HUNTR).
class GuestTag extends StatelessWidget {
  const GuestTag({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: HuntrColors.orange.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('GUEST',
            style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w800,
                color: HuntrColors.orange)),
      );
}

/// "8m left": how long a guest chat has (the guest's next message resets it).
class TimeLeftChip extends StatelessWidget {
  const TimeLeftChip({super.key, required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('guestTimeLeft'),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('${minutes}m left',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: minutes <= 2 ? HuntrColors.orange : HuntrColors.muted)),
      );
}

/// The start of a guest's empty chat: whom they're writing to, in a line.
class GuestIntro extends StatelessWidget {
  const GuestIntro({super.key, required this.to});

  final String to;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Say hi to $to',
              key: const Key('guestChatIntro'),
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('You’re anonymous. No account needed.',
              textAlign: TextAlign.center,
              style: TextStyle(color: HuntrColors.muted, height: 1.45)),
        ]),
      );
}

/// While [on]: a light that travels around [child]'s edge over a soft
/// glow that breathes with it (one still glow with reduced motion).
class GlowBox extends StatefulWidget {
  const GlowBox({super.key, required this.on, required this.child});

  final bool on;
  final Widget child;

  @override
  State<GlowBox> createState() => _GlowBoxState();
}

class _GlowBoxState extends State<GlowBox> with SingleTickerProviderStateMixin {
  // one turn of the light around the edge (two breaths of the glow)
  late final _turn = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _run();
  }

  @override
  void didUpdateWidget(GlowBox old) {
    super.didUpdateWidget(old);
    _run();
  }

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _run() {
    if (widget.on && !_still) {
      if (!_turn.isAnimating) _turn.repeat();
    } else {
      _turn.stop();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.on) return widget.child;
    return AnimatedBuilder(
      animation: _turn,
      child: widget.child,
      builder: (context, child) {
        final turn = _still ? 0.0 : _turn.value;
        // the glow breathes twice a turn: 0..1..0..1..0
        final breath = _still ? 0.5 : (1 - math.cos(turn * 4 * math.pi)) / 2;
        return Container(
          key: const Key('guestMessageGlow'),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                  color: HuntrColors.orange
                      .withValues(alpha: 0.10 + 0.22 * breath),
                  blurRadius: 10 + 14 * breath),
            ],
          ),
          child: CustomPaint(
            foregroundPainter: _EdgeLight(turn: turn, still: _still),
            child: child,
          ),
        );
      },
    );
  }
}

/// The edge: a faint orange line, and a brighter light along it at [turn]
/// (0..1 around).
class _EdgeLight extends CustomPainter {
  const _EdgeLight({required this.turn, required this.still});

  final double turn;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final edge = RRect.fromRectAndRadius(
        rect.deflate(0.75), Radius.circular(math.min(28, size.height / 2)));
    canvas.drawRRect(
        edge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = HuntrColors.orange.withValues(alpha: still ? 0.8 : 0.35));
    if (still) return;
    canvas.drawRRect(
        edge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..shader = SweepGradient(
            colors: [
              HuntrColors.orange.withValues(alpha: 0),
              HuntrColors.orange,
              const Color(0xFFFFC48A),
              HuntrColors.orange,
              HuntrColors.orange.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.08, 0.12, 0.16, 0.24],
            transform: GradientRotation(turn * 2 * math.pi),
          ).createShader(rect));
  }

  @override
  bool shouldRepaint(_EdgeLight old) => old.turn != turn || old.still != still;
}
