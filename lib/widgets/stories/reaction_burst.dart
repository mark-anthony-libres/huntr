import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';

/// A reaction just sent, played once over the story: the emoji pops up big
/// in an orange glow, little copies fly out around it, and it all floats
/// away. Give it a new key to play it again. With [wave] the big one waves
/// side to side (a tap's 👋).
class ReactionBurst extends StatefulWidget {
  const ReactionBurst(
      {super.key, required this.emoji, this.onDone, this.wave = false});

  final String emoji;
  final VoidCallback? onDone;
  final bool wave;

  /// Plays [emoji] once over everything (centred on the screen), e.g. a tap
  /// just sent from a profile.
  static void show(BuildContext context, String emoji, {bool wave = false}) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        // over everything, outside any page: the text needs its own style
        // (without one, Flutter marks it with a yellow underline)
        child: Material(
          type: MaterialType.transparency,
          child: Center(
            child: ReactionBurst(
                key: const Key('reactionBurstOverlay'),
                emoji: emoji,
                wave: wave,
                onDone: () => entry.remove()),
          ),
        ),
      ),
    );
    overlay.insert(entry);
  }

  @override
  State<ReactionBurst> createState() => _ReactionBurstState();
}

class _ReactionBurstState extends State<ReactionBurst>
    with SingleTickerProviderStateMixin {
  late final _play = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1300))
    ..forward().whenComplete(() => widget.onDone?.call());

  /// Pops in past full size, settles, then shrinks a little as it leaves.
  late final _size = TweenSequence([
    TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.25)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 25),
    TweenSequenceItem(
        tween: Tween(begin: 1.25, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 15),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 30),
    TweenSequenceItem(
        tween:
            Tween(begin: 1.0, end: 0.8).chain(CurveTween(curve: Curves.easeIn)),
        weight: 30),
  ]).animate(_play);

  late final _leaving = CurvedAnimation(
      parent: _play, curve: const Interval(0.7, 1, curve: Curves.easeIn));

  late final _flying = CurvedAnimation(
      parent: _play, curve: const Interval(0.1, 0.75, curve: Curves.easeOut));

  static const _sparks = 8;

  @override
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _play,
          builder: (context, _) {
            final fade = 1 - _leaving.value;
            final rise = -60 * _leaving.value;
            return Opacity(
              opacity: fade,
              child: Transform.translate(
                offset: Offset(0, rise),
                child: SizedBox.square(
                  dimension: 260,
                  child: Stack(alignment: Alignment.center, children: [
                    // the glow
                    Transform.scale(
                      scale: 0.4 + _flying.value,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(colors: [
                            HuntrColors.orange
                                .withValues(alpha: 0.55 * (1 - _flying.value)),
                            HuntrColors.orange.withValues(alpha: 0),
                          ]),
                        ),
                      ),
                    ),
                    // the little ones flying out
                    for (var i = 0; i < _sparks; i++)
                      Transform.translate(
                        offset: Offset.fromDirection(
                            i * 2 * math.pi / _sparks - math.pi / 2,
                            30 + 90 * _flying.value),
                        child: Opacity(
                          opacity: (1 - _flying.value).clamp(0, 1),
                          child: Text(widget.emoji,
                              style: const TextStyle(fontSize: 22)),
                        ),
                      ),
                    // the big one (waving: rocks from its wrist, slowing)
                    Transform.rotate(
                      angle: widget.wave
                          ? math.sin(_play.value * 6 * math.pi) *
                              0.45 *
                              (1 - _play.value)
                          : 0,
                      alignment: const Alignment(0.3, 0.7),
                      child: Transform.scale(
                        scale: _size.value,
                        child: Text(widget.emoji,
                            style: const TextStyle(fontSize: 110, shadows: [
                              Shadow(color: Colors.black54, blurRadius: 18),
                            ])),
                      ),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      );
}
