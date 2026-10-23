import 'package:flutter/material.dart';

import '../../theme.dart';

/// Picks which [window] of a longer video to keep: the whole video is the
/// bar, the window an orange frame on it to drag (or tap the bar to put it
/// there). The frame is always exactly [window] long; a line shows what's
/// playing.
class TrimWindow extends StatelessWidget {
  const TrimWindow({
    super.key,
    required this.total,
    required this.window,
    required this.start,
    required this.position,
    required this.onChanged,
    this.onChangeEnd,
    this.background,
  });

  /// Shown along the bar, e.g. frames of the video (a filmstrip).
  final Widget? background;

  final Duration total;
  final Duration window;
  final Duration start;
  final Duration position;
  final ValueChanged<Duration> onChanged;
  final VoidCallback? onChangeEnd;

  /// The latest start that still fits a whole window.
  Duration get _lastStart => total - window;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final width = box.maxWidth;
        final totalMs = total.inMilliseconds.clamp(1, 1 << 31);
        final frame = (width * window.inMilliseconds / totalMs)
            .clamp(28.0, width)
            .toDouble();
        final room = width - frame;
        double leftOf(Duration d) => _lastStart.inMilliseconds <= 0
            ? 0
            : room * d.inMilliseconds / _lastStart.inMilliseconds;
        Duration startAt(double left) => Duration(
            milliseconds: (_lastStart.inMilliseconds *
                    (room <= 0 ? 0 : (left / room).clamp(0.0, 1.0)))
                .round());
        final left = leftOf(start);
        final playhead = (width * position.inMilliseconds / totalMs)
            .clamp(0.0, width)
            .toDouble();
        return GestureDetector(
          key: const Key('storyTrim'),
          behavior: HitTestBehavior.opaque,
          // tap: the frame centred there
          onTapUp: (d) {
            onChanged(startAt(d.localPosition.dx - frame / 2));
            onChangeEnd?.call();
          },
          onHorizontalDragUpdate: (d) =>
              onChanged(startAt(leftOf(start) + d.delta.dx)),
          onHorizontalDragEnd: (_) => onChangeEnd?.call(),
          child: SizedBox(
            height: 64,
            child: Stack(clipBehavior: Clip.none, children: [
              // the whole video (its frames, drawn once)
              Positioned.fill(
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: HuntrColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: HuntrColors.border),
                  ),
                  child: background,
                ),
              ),
              // dimmed outside the part kept
              if (background != null) ...[
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: left,
                  child: const IgnorePointer(child: _Dim(left: true)),
                ),
                Positioned(
                  left: left + frame,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: const IgnorePointer(child: _Dim(left: false)),
                ),
              ],
              // the part kept
              Positioned(
                left: left,
                top: 0,
                bottom: 0,
                width: frame,
                child: Container(
                  key: const Key('storyTrimFrame'),
                  decoration: BoxDecoration(
                    // the frames show through; without them, a tint
                    color: background == null
                        ? HuntrColors.orange.withValues(alpha: 0.22)
                        : null,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: HuntrColors.orange, width: 3),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.drag_indicator_rounded,
                      color: Colors.white70,
                      size: 20,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 4)]),
                ),
              ),
              // what's playing
              Positioned(
                left: playhead - 1,
                top: 4,
                bottom: 4,
                width: 2,
                child: const IgnorePointer(
                  child: ColoredBox(color: Colors.white),
                ),
              ),
            ]),
          ),
        );
      });
}

/// The bar outside the part kept, dimmed (rounded at the bar's own end).
class _Dim extends StatelessWidget {
  const _Dim({required this.left});

  final bool left;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: left
              ? const BorderRadius.horizontal(left: Radius.circular(12))
              : const BorderRadius.horizontal(right: Radius.circular(12)),
        ),
      );
}
