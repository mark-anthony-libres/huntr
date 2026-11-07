import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../avatar.dart';

/// The welcome's picture: a sonar in a rounded card, its sweep turning past
/// a few people around me (stand-in portraits, never real members) and faint
/// specks. The sweep turns for a while, then rests (and not at all when the
/// device asks for less motion).
class NearbyRadar extends StatefulWidget {
  const NearbyRadar({super.key, this.size = 290});

  final double size;

  @override
  State<NearbyRadar> createState() => _NearbyRadarState();
}

/// Someone around me: where in the card (shares of its size) and the colour
/// of their stand-in portrait.
typedef _Near = ({double x, double y, double hue});

const List<_Near> _around = [
  (x: 0.27, y: 0.26, hue: 24),
  (x: 0.39, y: 0.48, hue: 200),
  (x: 0.24, y: 0.62, hue: 300),
  (x: 0.74, y: 0.74, hue: 140),
];

/// Faint specks, like far-off people (shares of the card's size).
const List<Offset> _specks = [
  Offset(0.08, 0.18),
  Offset(0.41, 0.04),
  Offset(0.88, 0.32),
  Offset(0.12, 0.86),
  Offset(0.58, 0.92),
];

/// The sonar's middle, a little right of the card's.
const _middle = Offset(0.63, 0.46);

class _NearbyRadarState extends State<NearbyRadar>
    with TickerProviderStateMixin {
  late final _sweep = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200));
  late final _enter = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _enter.value = 1;
      _sweep.value = 0.15;
    } else {
      _enter.forward();
      _sweep.repeat(count: 6);
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    _enter.dispose();
    super.dispose();
  }

  /// The part of the entrance from [start] to [end] (shares of it), eased.
  double _step(double start, double end) => Curves.easeOutBack
      .transform(((_enter.value - start) / (end - start)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: HuntrColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: HuntrColors.border),
      ),
      child: AnimatedBuilder(
        animation: Listenable.merge([_sweep, _enter]),
        builder: (context, _) {
          final dot = size * 0.075;
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _SonarPainter(
                      turn: _sweep.value,
                      shown: Curves.easeOut.transform(_enter.value)),
                ),
              ),
              for (final speck in _specks)
                Positioned(
                  left: speck.dx * size,
                  top: speck.dy * size,
                  child: Opacity(
                    opacity: 0.7 * _enter.value,
                    child: Container(
                        width: 3,
                        height: 3,
                        decoration: const BoxDecoration(
                            color: Colors.white, shape: BoxShape.circle)),
                  ),
                ),
              for (final (i, near) in _around.indexed)
                Positioned(
                  left: near.x * size - dot / 2,
                  top: near.y * size - dot / 2,
                  child: Transform.scale(
                    scale: _step(0.3 + i * 0.12, 0.65 + i * 0.12),
                    child: Container(
                      width: dot,
                      height: dot,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.7),
                            width: 1.5),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.white.withValues(alpha: 0.25),
                              blurRadius: 8),
                        ],
                      ),
                      child: ClipOval(child: DefaultPortrait(hue: near.hue)),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Rings, crosshairs and the turning sweep, around [_middle].
class _SonarPainter extends CustomPainter {
  const _SonarPainter({required this.turn, required this.shown});

  /// The sweep's angle, in turns.
  final double turn;

  /// The entrance, 0 to 1.
  final double shown;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(_middle.dx * size.width, _middle.dy * size.height);
    final unit = size.shortestSide;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.13 * shown);
    for (final share in const [0.14, 0.27, 0.42, 0.6, 0.8]) {
      canvas.drawCircle(center, unit * share * (0.6 + 0.4 * shown), line);
    }
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), line);
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), line);

    // the sweep: a bright edge fading out behind it
    final reach = unit * 0.8;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(turn * 2 * math.pi - math.pi / 2);
    final rect = Rect.fromCircle(center: Offset.zero, radius: reach);
    canvas.drawArc(
      rect,
      -math.pi / 2.2,
      math.pi / 2.2,
      true,
      Paint()
        ..shader = SweepGradient(
          startAngle: -math.pi / 2.2,
          endAngle: 0,
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.22 * shown),
          ],
        ).createShader(rect),
    );
    canvas.drawLine(
        Offset.zero,
        Offset(reach, 0),
        Paint()
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.45 * shown));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SonarPainter oldDelegate) =>
      oldDelegate.turn != turn || oldDelegate.shown != shown;
}
