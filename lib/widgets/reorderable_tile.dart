import 'package:flutter/material.dart';

import '../theme.dart';

/// One tile of a grid that can be rearranged: hold it, then drag it onto
/// another tile to move it there ([onMove] gets the from and to indexes).
/// The tile under the finger is outlined while dragging.
class ReorderableTile extends StatelessWidget {
  const ReorderableTile({
    super.key,
    required this.index,
    required this.onMove,
    required this.child,
    this.enabled = true,
    this.radius = 16,
  });

  final int index;
  final void Function(int from, int to) onMove;
  final Widget child;

  /// Off while the tile is busy (e.g. being removed).
  final bool enabled;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      return DragTarget<int>(
        onWillAcceptWithDetails: (details) => details.data != index,
        onAcceptWithDetails: (details) => onMove(details.data, index),
        builder: (context, candidates, _) {
          final tile = Stack(fit: StackFit.expand, children: [
            child,
            if (candidates.isNotEmpty)
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: HuntrColors.orange, width: 3),
                  ),
                ),
              ),
          ]);
          if (!enabled) return tile;
          return LongPressDraggable<int>(
            data: index,
            hapticFeedbackOnStart: true,
            // the tile, lifted, under the finger
            feedback: Container(
              width: box.maxWidth * 1.05,
              height: box.maxHeight * 1.05,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black54,
                      blurRadius: 18,
                      offset: Offset(0, 8)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Material(
                    type: MaterialType.transparency,
                    child: IgnorePointer(child: child)),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.3, child: child),
            child: tile,
          );
        },
      );
    });
  }
}
