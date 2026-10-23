import 'package:flutter/material.dart';

import '../../theme.dart';

/// The rounded card the Me sections use for their states.
class _StateCard extends StatelessWidget {
  const _StateCard({required this.child, this.accent});
  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: HuntrColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: (accent ?? HuntrColors.border).withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }
}

class _StateIcon extends StatelessWidget {
  const _StateIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
          shape: BoxShape.circle, color: color.withValues(alpha: 0.15)),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

/// Something couldn't be loaded: what, why (in plain words) and a clear
/// way to try again.
class LoadFailedCard extends StatelessWidget {
  const LoadFailedCard({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
    this.messageKey,
    this.retryKey,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;
  final Key? messageKey;
  final Key? retryKey;

  @override
  Widget build(BuildContext context) {
    return _StateCard(
      accent: HuntrColors.coral,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _StateIcon(
            icon: Icons.cloud_off_rounded, color: HuntrColors.coral),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, height: 1.3)),
            const SizedBox(height: 4),
            Text(message,
                key: messageKey,
                style: const TextStyle(color: HuntrColors.muted, height: 1.4)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: retryKey,
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: HuntrColors.orange,
                side: BorderSide(
                    color: HuntrColors.orange.withValues(alpha: 0.7)),
                shape: const StadiumBorder(),
                minimumSize: const Size(0, 40),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Nothing here yet: a short explanation and the action that starts it.
class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionKey,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    return _StateCard(
      child: Column(children: [
        _StateIcon(icon: icon, color: HuntrColors.orange),
        const SizedBox(height: 12),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: HuntrColors.muted, height: 1.4)),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 14),
          FilledButton.icon(
            key: actionKey,
            onPressed: onAction,
            style: FilledButton.styleFrom(
              backgroundColor: HuntrColors.orange,
              foregroundColor: Colors.black,
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: Text(actionLabel!),
          ),
        ],
      ]),
    );
  }
}

/// A limit was reached: shown as a calm note, not an error.
class LimitNotice extends StatelessWidget {
  const LimitNotice({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: HuntrColors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HuntrColors.orange.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(Icons.info_outline_rounded, color: HuntrColors.orange, size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Text(message,
                style: const TextStyle(color: HuntrColors.muted, height: 1.4))),
      ]),
    );
  }
}

/// Placeholder rows while a list loads (instead of a lone spinner).
class LoadingRows extends StatefulWidget {
  const LoadingRows({super.key, this.count = 2, this.height = 84});
  final int count;
  final double height;

  @override
  State<LoadingRows> createState() => _LoadingRowsState();
}

class _LoadingRowsState extends State<LoadingRows>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_pulse),
      child: Column(children: [
        for (var i = 0; i < widget.count; i++)
          Container(
            height: widget.height,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: HuntrColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: HuntrColors.border),
            ),
            child: Row(children: [
              Container(
                width: 60,
                decoration: BoxDecoration(
                    color: HuntrColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(10)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                          width: 120,
                          height: 14,
                          color: HuntrColors.surfaceHigh),
                      const SizedBox(height: 8),
                      Container(
                          width: 80,
                          height: 12,
                          color: HuntrColors.surfaceHigh),
                    ]),
              ),
            ]),
          ),
      ]),
    );
  }
}
