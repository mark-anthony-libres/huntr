import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The blue of the check (as on X and Instagram).
const verifiedBlue = Color(0xFF1D9BF0);

/// The blue check by a verified person's name: our team confirmed who they
/// are from documents they sent. Hovering says so briefly; tapping it (when
/// [interactive]) explains it in full. Lists leave it not [interactive], so
/// a tap opens the profile as usual.
///
/// It's alive - a light sweeps across it every few seconds, with a little
/// pop - so a check typed into a name (an emoji, a symbol) can't pass for
/// it. Still for people who turn animations off.
class VerifiedBadge extends StatefulWidget {
  const VerifiedBadge(
      {super.key,
      this.size = 20,
      this.name,
      this.interactive = true,
      this.tooltip = 'Verified: identity confirmed by HUNTR',
      this.semanticLabel = 'Verified'});

  final double size;

  /// Whose it is, for the explanation ("Sam is verified").
  final String? name;
  final bool interactive;

  /// What hovering says (HUNTR's own posts say they're official).
  final String tooltip;
  final String semanticLabel;

  @override
  State<VerifiedBadge> createState() => _VerifiedBadgeState();
}

class _VerifiedBadgeState extends State<VerifiedBadge>
    with SingleTickerProviderStateMixin {
  /// One sweep of light, with the pop.
  late final _shine = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100), value: 1);

  /// A sweep every few seconds; between them nothing moves (no frames).
  Timer? _every;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _every?.cancel();
    _every = null;
    if (MediaQuery.of(context).disableAnimations) {
      _shine
        ..stop()
        ..value = 1;
      return;
    }
    _every = Timer.periodic(
        const Duration(milliseconds: 3200), (_) => _shine.forward(from: 0));
  }

  @override
  void dispose() {
    _every?.cancel();
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final check = AnimatedBuilder(
      animation: _shine,
      builder: (context, icon) {
        // the sweep and the pop (still at the end, between sweeps)
        final t = _shine.value;
        final pop = 1 + 0.12 * math.sin(math.pi * t);
        return Transform.scale(
          scale: pop,
          child: ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) => LinearGradient(
              begin: const Alignment(-1, -0.6),
              end: const Alignment(1, 0.6),
              colors: [
                Colors.transparent,
                Colors.white.withValues(alpha: 0.85),
                Colors.transparent,
              ],
              // the band of light, moving from off one side to off the other
              stops: [t * 1.6 - 0.45, t * 1.6 - 0.3, t * 1.6 - 0.15],
            ).createShader(bounds),
            child: icon,
          ),
        );
      },
      child: Icon(Icons.verified_rounded,
          key: const Key('verifiedBadge'),
          size: widget.size,
          color: verifiedBlue,
          semanticLabel: widget.semanticLabel),
    );
    return Tooltip(
      message: widget.tooltip,
      child: !widget.interactive
          ? check
          : InkResponse(
              key: const Key('verifiedBadgeButton'),
              radius: widget.size,
              onTap: () => showVerifiedInfo(context, name: widget.name),
              child: check,
            ),
    );
  }
}

/// What the blue check means, in plain words.
Future<void> showVerifiedInfo(BuildContext context, {String? name}) {
  final who = name == null || name.trim().isEmpty ? 'This person' : name.trim();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    // as tall as it needs (it scrolls on a short screen)
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        key: const Key('verifiedInfo'),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.verified_rounded, size: 56, color: verifiedBlue),
          const SizedBox(height: 12),
          Text('$who is verified',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const Text(
            'They sent us an ID document and our team checked that it '
            'matches them, so they are who they say they are.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.45),
          ),
          const SizedBox(height: 16),
          const _Point(
              icon: Icons.shield_outlined,
              text: 'We verify people to keep out fake accounts and anyone '
                  'pretending to be someone else.'),
          const _Point(
              icon: Icons.lock_outline_rounded,
              text: 'Their documents stay private: nobody on HUNTR sees '
                  'them.'),
          const _Point(
              icon: Icons.handshake_outlined,
              text: 'A blue check confirms who someone is, not how they '
                  'behave, so still chat and meet safely.'),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: verifiedBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder()),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    ),
  );
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: verifiedBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: HuntrColors.muted, fontSize: 14, height: 1.4)),
          ),
        ]),
      );
}
