import 'dart:async';

import 'package:flutter/material.dart';

import '../services/rate_limit.dart';
import '../theme.dart';

/// Covers the whole app while the backend refuses my requests (HTTP 429):
/// what happened, and a countdown until it's over. It goes away on its own;
/// the screen underneath is as it was.
class RateLimitOverlay extends StatelessWidget {
  const RateLimitOverlay({super.key, required this.gate, required this.child});

  final RateLimitGate gate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: gate,
      builder: (context, _) => Stack(children: [
        child,
        if (gate.active) Positioned.fill(child: RateLimitScreen(gate: gate)),
      ]),
    );
  }
}

class RateLimitScreen extends StatefulWidget {
  const RateLimitScreen({super.key, required this.gate});

  final RateLimitGate gate;

  @override
  State<RateLimitScreen> createState() => _RateLimitScreenState();
}

class _RateLimitScreenState extends State<RateLimitScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!widget.gate.active) {
        widget.gate.clear(); // over: the app is usable again
      } else if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final until = widget.gate.until ?? DateTime.now();
    final left = until.difference(DateTime.now());
    final seconds = left.isNegative ? 0 : (left.inMilliseconds / 1000).ceil();
    final clock =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Material(
      key: const Key('rateLimitScreen'),
      color: HuntrColors.night,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: HuntrColors.orange.withValues(alpha: 0.12),
                    border: Border.all(
                        color: HuntrColors.orange.withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.hourglass_top_rounded,
                      size: 46, color: HuntrColors.orange),
                ),
                const SizedBox(height: 28),
                const Text('Slow down a little',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                const Text(
                  'You made a lot of requests in a short time, so Huntr has '
                  'paused your account for a few minutes. This keeps Huntr '
                  'fast and safe for everyone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: HuntrColors.muted, fontSize: 15, height: 1.45),
                ),
                const SizedBox(height: 32),
                const Text('You can use Huntr again in',
                    style: TextStyle(color: HuntrColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                Text(clock,
                    key: const Key('rateLimitCountdown'),
                    style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        color: HuntrColors.orange,
                        fontFeatures: [FontFeature.tabularFigures()])),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: HuntrColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: HuntrColors.border),
                  ),
                  child: const Row(children: [
                    Icon(Icons.info_outline_rounded,
                        size: 20, color: HuntrColors.muted),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This screen closes by itself. Messages that '
                        'didn’t send can be retried afterwards.',
                        style: TextStyle(
                            color: HuntrColors.muted,
                            fontSize: 13,
                            height: 1.4),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
