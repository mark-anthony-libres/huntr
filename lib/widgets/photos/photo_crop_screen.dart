import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../theme.dart';

/// The square area of the photo shown in the viewport, as fractions 0-1 of
/// the photo. [displaySize] is the photo's size inside the viewer before any
/// zoom; [transform] is the viewer's current zoom and position.
PhotoCrop cropForViewport({
  required Size displaySize,
  required double viewport,
  required Matrix4 transform,
}) {
  final inverse = Matrix4.inverted(transform);
  final topLeft = MatrixUtils.transformPoint(inverse, Offset.zero);
  final bottomRight =
      MatrixUtils.transformPoint(inverse, Offset(viewport, viewport));
  double fraction(double value, double size) => (value / size).clamp(0.0, 1.0);
  final x = fraction(topLeft.dx, displaySize.width);
  final y = fraction(topLeft.dy, displaySize.height);
  return PhotoCrop(
    x: x,
    y: y,
    width: fraction(bottomRight.dx, displaySize.width) - x,
    height: fraction(bottomRight.dy, displaySize.height) - y,
  );
}

/// Square (1:1) crop editor: drag to move, pinch / scroll / slider to zoom.
/// What's inside the frame is exactly what's kept. Pops with a [PhotoCrop],
/// or null when cancelled. The photo itself is cropped by the backend.
class PhotoCropScreen extends StatefulWidget {
  const PhotoCropScreen({
    super.key,
    required this.image,
    required this.imageSize,
    this.title = 'Crop photo',
    this.confirmLabel = 'Use photo',
  });

  final ImageProvider image;

  /// The photo's real size in pixels.
  final Size imageSize;
  final String title;
  final String confirmLabel;

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  static const _maxZoom = 5.0;

  final _transform = TransformationController();
  double? _viewport;
  double _zoom = 1;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
  }

  void _onTransform() {
    final zoom = _transform.value.getMaxScaleOnAxis();
    if ((zoom - _zoom).abs() > 0.001) setState(() => _zoom = zoom);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// The photo scaled so it just covers the square viewport.
  Size _displaySize(double viewport) {
    final scale = math.max(
        viewport / widget.imageSize.width, viewport / widget.imageSize.height);
    return Size(
        widget.imageSize.width * scale, widget.imageSize.height * scale);
  }

  /// Zoomed in by [zoom] around the frame's middle, centered on [focal]
  /// (a point of the unzoomed photo), always covering the frame.
  Matrix4 _framed(double viewport, double zoom, Offset focal) {
    final display = _displaySize(viewport);
    final dx = (viewport / 2 - focal.dx * zoom)
        .clamp(viewport - display.width * zoom, 0.0);
    final dy = (viewport / 2 - focal.dy * zoom)
        .clamp(viewport - display.height * zoom, 0.0);
    return Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(zoom, zoom, 1, 1);
  }

  void _center(double viewport) {
    final display = _displaySize(viewport);
    _transform.value =
        _framed(viewport, 1, Offset(display.width / 2, display.height / 2));
  }

  void _setZoom(double zoom, double viewport) {
    final middle = Offset(viewport / 2, viewport / 2);
    final focal =
        MatrixUtils.transformPoint(Matrix4.inverted(_transform.value), middle);
    _transform.value = _framed(viewport, zoom, focal);
  }

  void _confirm() {
    final viewport = _viewport;
    if (viewport == null) return;
    Navigator.of(context).pop(cropForViewport(
      displaySize: _displaySize(viewport),
      viewport: viewport,
      transform: _transform.value,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          tooltip: 'Cancel',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final viewport = math
              .min(math.min(box.maxWidth - 40, box.maxHeight - 220), 560.0)
              .clamp(160.0, 560.0);
          if (_viewport != viewport) {
            _viewport = viewport;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _center(viewport);
            });
          }
          final display = _displaySize(viewport);
          return Column(
            children: [
              const SizedBox(height: 16),
              const Text('Drag to move · pinch or scroll to zoom',
                  style: TextStyle(color: HuntrColors.muted)),
              const SizedBox(height: 16),
              Center(
                child: SizedBox.square(
                  dimension: viewport,
                  child: Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: InteractiveViewer(
                        key: const Key('photoCropViewer'),
                        transformationController: _transform,
                        constrained: false,
                        minScale: 1,
                        maxScale: _maxZoom,
                        boundaryMargin: EdgeInsets.zero,
                        child: SizedBox(
                          width: display.width,
                          height: display.height,
                          child: Image(image: widget.image, fit: BoxFit.fill),
                        ),
                      ),
                    ),
                    // the frame and a rule-of-thirds grid
                    IgnorePointer(
                      child: CustomPaint(
                        size: Size.square(viewport),
                        painter: _CropFramePainter(),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: viewport,
                child: Row(children: [
                  const Icon(Icons.zoom_out, color: HuntrColors.muted),
                  Expanded(
                    child: Slider(
                      key: const Key('photoCropZoom'),
                      value: _zoom.clamp(1.0, _maxZoom),
                      min: 1,
                      max: _maxZoom,
                      onChanged: (zoom) => _setZoom(zoom, viewport),
                    ),
                  ),
                  const Icon(Icons.zoom_in, color: HuntrColors.muted),
                ]),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: const StadiumBorder()),
                        onPressed: () => _center(viewport),
                        child: const Text('Reset'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        key: const Key('photoCropConfirm'),
                        onPressed: _confirm,
                        child: Text(widget.confirmLabel),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _CropFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final frame =
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16));
    canvas.drawRRect(
        frame,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = HuntrColors.orange);
    final grid = Paint()
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.25);
    for (var i = 1; i < 3; i++) {
      final at = size.width * i / 3;
      canvas.drawLine(Offset(at, 0), Offset(at, size.height), grid);
      canvas.drawLine(Offset(0, at), Offset(size.width, at), grid);
    }
  }

  @override
  bool shouldRepaint(_CropFramePainter oldDelegate) => false;
}
