import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Explore's All filters button. With filters on it's orange, its badge
/// says how many, and a ring pulses out of it every few seconds (so it's
/// clear the list is filtered). [raised]: the copy floating over the list
/// once the header has scrolled away (a solid background and a shadow).
class FiltersButton extends StatefulWidget {
  const FiltersButton({
    super.key,
    required this.count,
    required this.onPressed,
    this.raised = false,
  });

  /// How many filters are on (0: none).
  final int count;
  final VoidCallback onPressed;
  final bool raised;

  @override
  State<FiltersButton> createState() => _FiltersButtonState();
}

class _FiltersButtonState extends State<FiltersButton>
    with SingleTickerProviderStateMixin {
  /// One pulse of the ring; then a pause (a timer, so nothing animates in
  /// between) and the next.
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1300));
  Timer? _next;

  static const _pause = Duration(milliseconds: 1700);

  bool get _on => widget.count > 0;

  @override
  void initState() {
    super.initState();
    if (_on) _run();
  }

  @override
  void didUpdateWidget(FiltersButton old) {
    super.didUpdateWidget(old);
    final wasOn = old.count > 0;
    if (_on && !wasOn) {
      _run();
    } else if (!_on && wasOn) {
      _next?.cancel();
      _pulse.reset();
    }
  }

  void _run() {
    _next?.cancel();
    if (!mounted || !_on) return;
    _pulse.forward(from: 0).whenComplete(() {
      if (mounted && _on) _next = Timer(_pause, _run);
    });
  }

  @override
  void dispose() {
    _next?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = _on;
    return SizedBox.square(
      dimension: 40,
      child: Stack(clipBehavior: Clip.none, children: [
        // the ring, out from the button and fading
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => CustomPaint(
                painter: _Ring(on ? Curves.easeOut.transform(_pulse.value) : 0,
                    HuntrColors.orange),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: widget.raised
                  ? [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 12,
                          offset: const Offset(0, 4))
                    ]
                  : const [],
            ),
            child: IconButton.outlined(
              key: const Key('allFilters'),
              tooltip: on ? 'All filters (${widget.count} on)' : 'All filters',
              style: IconButton.styleFrom(
                fixedSize: const Size(40, 40),
                minimumSize: const Size(40, 40),
                padding: EdgeInsets.zero,
                iconSize: 20,
                side: BorderSide(
                    color: on ? HuntrColors.orange : const Color(0xFF353944),
                    width: 1.2),
                backgroundColor: widget.raised
                    ? HuntrColors.surfaceHigh
                    : HuntrColors.night.withValues(alpha: 0.4),
                foregroundColor: on ? HuntrColors.orange : Colors.white,
              ),
              icon: const Icon(Icons.tune),
              onPressed: widget.onPressed,
            ),
          ),
        ),
        // how many are on
        Positioned(
          top: -4,
          right: -4,
          child: AnimatedScale(
            scale: on ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: Container(
              key: const Key('filtersOnCount'),
              constraints: const BoxConstraints(minWidth: 18),
              height: 18,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: HuntrColors.orange,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: HuntrColors.night, width: 2),
              ),
              child: Text('${widget.count}',
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 10,
                      height: 1,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Ring extends CustomPainter {
  _Ring(this.t, this.color);

  /// How far this pulse is (0-1; 0: none).
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final r = size.shortestSide / 2;
    canvas.drawCircle(
        size.center(Offset.zero),
        r + 12 * t,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - t) + 0.5
          ..color = color.withValues(alpha: 0.6 * (1 - t)));
  }

  @override
  bool shouldRepaint(_Ring old) => old.t != t || old.color != color;
}
