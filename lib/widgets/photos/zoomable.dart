import 'package:flutter/material.dart';

/// A photo or video shown full screen that zooms: pinch (or a trackpad, or
/// Ctrl + scroll) in and out, drag around once zoomed in, and a double tap
/// zooms in where it was tapped, or back out. Never smaller than it fits.
/// [onZoomed] says when it's zoomed in, so a swipe moves the picture, not
/// to the next one.
class Zoomable extends StatefulWidget {
  const Zoomable({super.key, required this.child, this.onZoomed});

  final Widget child;
  final ValueChanged<bool>? onZoomed;

  static const maxScale = 5.0;

  /// How far a double tap zooms in.
  static const doubleTapScale = 2.5;

  @override
  State<Zoomable> createState() => _ZoomableState();
}

class _ZoomableState extends State<Zoomable>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final AnimationController _animation;
  Matrix4Tween? _tween;
  Offset _tapAt = Offset.zero;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_changed);
    _animation = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220))
      ..addListener(() => _transform.value = _tween!.evaluate(
          CurvedAnimation(parent: _animation, curve: Curves.easeOut)));
  }

  void _changed() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) {
      setState(() => _zoomed = zoomed);
      widget.onZoomed?.call(zoomed);
    }
  }

  void _doubleTap() {
    final Matrix4 to;
    if (_zoomed) {
      to = Matrix4.identity();
    } else {
      // the tapped spot stays where it is
      const s = Zoomable.doubleTapScale;
      to = Matrix4.identity()
        ..translateByDouble(-_tapAt.dx * (s - 1), -_tapAt.dy * (s - 1), 0, 1)
        ..scaleByDouble(s, s, 1, 1);
    }
    _tween = Matrix4Tween(begin: _transform.value, end: to);
    _animation.forward(from: 0);
  }

  @override
  void dispose() {
    _transform.removeListener(_changed);
    _animation.dispose();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onDoubleTapDown: (details) => _tapAt = details.localPosition,
        onDoubleTap: _doubleTap,
        child: InteractiveViewer(
          transformationController: _transform,
          minScale: 1,
          maxScale: Zoomable.maxScale,
          // not zoomed: a one-finger swipe goes to the next one
          panEnabled: _zoomed,
          child: widget.child,
        ),
      );
}
