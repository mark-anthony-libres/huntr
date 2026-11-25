import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../theme.dart';
import 'photo_edits.dart';

/// The area of the photo shown in the viewport (square, or [viewportHeight]
/// tall), as fractions 0-1 of the photo. [displaySize] is the photo's size
/// inside the viewer before any zoom; [transform] is the viewer's current
/// zoom and position.
PhotoCrop cropForViewport({
  required Size displaySize,
  required double viewport,
  double? viewportHeight,
  required Matrix4 transform,
}) {
  final inverse = Matrix4.inverted(transform);
  final topLeft = MatrixUtils.transformPoint(inverse, Offset.zero);
  final bottomRight = MatrixUtils.transformPoint(
      inverse, Offset(viewport, viewportHeight ?? viewport));
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

/// What the crop screen gives back: the crop, and (a photo still to upload)
/// what was drawn or blurred on it.
class PhotoCropResult {
  const PhotoCropResult(this.crop, [this.strokes = const []]);

  final PhotoCrop crop;
  final List<PhotoStroke> strokes;
}

/// The crop screen's tools: moving the photo, drawing on it, blurring it.
enum _Tool { move, draw, blur }

/// The colours Draw has.
const _drawColors = [
  Colors.white,
  Colors.black,
  Color(0xFFFF7A1A),
  Color(0xFFFF5252),
  Color(0xFFFFC83D),
  Color(0xFF2EE59D),
  Color(0xFF3B82F6),
  Color(0xFFFF5CA8),
];

/// Square (1:1) crop editor: drag to move, pinch / scroll / slider to zoom.
/// What's inside the frame is exactly what's kept. With [editable] (a photo
/// not uploaded yet) it can also be drawn on and parts of it blurred (Draw,
/// Blur; Undo, Redo), baked into the photo before it's uploaded. Pops with a
/// [PhotoCropResult], or null when cancelled. The photo itself is cropped
/// by the backend.
class PhotoCropScreen extends StatefulWidget {
  const PhotoCropScreen({
    super.key,
    required this.image,
    required this.imageSize,
    this.title = 'Edit photo',
    this.confirmLabel = 'Use photo',
    this.editable = false,
  });

  /// Draw and Blur too (only before uploading: they change the photo).
  final bool editable;

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

  /// The tools are open (Edit): Move, Draw, Blur in place of the buttons.
  bool _editing = false;
  _Tool _tool = _Tool.move;
  final _strokes = <PhotoStroke>[];

  /// Strokes undone, the last undone last (Redo brings them back; a new
  /// stroke forgets them).
  final _undone = <PhotoStroke>[];

  /// Bumped whenever a stroke changes (they grow in place while drawn).
  int _version = 0;
  Color _color = _drawColors.first;

  /// Brush sizes on screen (logical pixels), whatever the zoom.
  double _drawSize = 8;
  double _blurSize = 36;

  /// The pointer drawing now (one at a time).
  int? _pointer;

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
    Navigator.of(context).pop(PhotoCropResult(
        cropForViewport(
          displaySize: _displaySize(viewport),
          viewport: viewport,
          transform: _transform.value,
        ),
        List.of(_strokes)));
  }

  /// A finger (or the mouse) down on the photo, while drawing or blurring:
  /// a new stroke (its size the brush's on screen, whatever the zoom).
  void _strokeStart(PointerDownEvent event, Size display) {
    if (_tool == _Tool.move || _pointer != null) return;
    _pointer = event.pointer;
    final onScreen = _tool == _Tool.draw ? _drawSize : _blurSize;
    setState(() {
      _undone.clear();
      _strokes.add(PhotoStroke(
        kind:
            _tool == _Tool.draw ? PhotoStrokeKind.paint : PhotoStrokeKind.blur,
        color: _color,
        width: onScreen / _zoom / display.width,
        points: [_fraction(event.localPosition, display)],
      ));
      _version++;
    });
  }

  void _strokeMove(PointerMoveEvent event, Size display) {
    if (event.pointer != _pointer || _strokes.isEmpty) return;
    setState(() {
      _strokes.last.points.add(_fraction(event.localPosition, display));
      _version++;
    });
  }

  void _strokeEnd(PointerEvent event) {
    if (event.pointer == _pointer) _pointer = null;
  }

  static Offset _fraction(Offset local, Size display) => Offset(
      (local.dx / display.width).clamp(0.0, 1.0),
      (local.dy / display.height).clamp(0.0, 1.0));

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() {
      _undone.add(_strokes.removeLast());
      _version++;
    });
  }

  void _redo() {
    if (_undone.isEmpty) return;
    setState(() {
      _strokes.add(_undone.removeLast());
      _version++;
    });
  }

  /// Zoom in or out a step, around the frame's middle.
  void _zoomBy(double step) {
    final viewport = _viewport;
    if (viewport == null) return;
    _setZoom((_zoom + step).clamp(1.0, _maxZoom), viewport);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        leading: IconButton(
          tooltip: 'Cancel',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // the tools: drawing on the photo, blurring parts of it
          if (widget.editable)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                key: const Key('photoEdit'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => setState(() {
                  _editing = !_editing;
                  if (!_editing) _tool = _Tool.move;
                }),
                icon: Icon(_editing ? Icons.check_rounded : Icons.brush_rounded,
                    size: 20),
                label: Text(_editing ? 'Done' : 'Edit',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          // room for the tools too, when there are some (the same either
          // way, so the photo doesn't move when they open)
          final viewport = math
              .min(
                  math.min(box.maxWidth - 32,
                      box.maxHeight - (widget.editable ? 400 : 230)),
                  560.0)
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
              const SizedBox(height: 10),
              _hint(),
              const SizedBox(height: 14),
              Center(
                child: SizedBox.square(
                  dimension: viewport,
                  child: Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: InteractiveViewer(
                        key: const Key('photoCropViewer'),
                        transformationController: _transform,
                        constrained: false,
                        minScale: 1,
                        maxScale: _maxZoom,
                        boundaryMargin: EdgeInsets.zero,
                        // drawing or blurring: a finger paints (zoom with
                        // the slider)
                        panEnabled: _tool == _Tool.move,
                        scaleEnabled: _tool == _Tool.move,
                        child: Listener(
                          key: const Key('photoEditCanvas'),
                          onPointerDown: (e) => _strokeStart(e, display),
                          onPointerMove: (e) => _strokeMove(e, display),
                          onPointerUp: _strokeEnd,
                          onPointerCancel: _strokeEnd,
                          child: PhotoWithStrokes(
                            image: widget.image,
                            size: display,
                            strokes: _strokes,
                            version: _version,
                          ),
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
              // zoom out, the zoom, zoom in; fit (back to the whole photo)
              SizedBox(
                width: viewport,
                child: Row(children: [
                  _SquareButton(
                    key: const Key('photoZoomOut'),
                    tooltip: 'Zoom out',
                    icon: Icons.zoom_out_rounded,
                    onPressed: _zoom > 1.001 ? () => _zoomBy(-0.5) : null,
                  ),
                  Expanded(
                    child: Slider(
                      key: const Key('photoCropZoom'),
                      value: _zoom.clamp(1.0, _maxZoom),
                      min: 1,
                      max: _maxZoom,
                      onChanged: (zoom) => _setZoom(zoom, viewport),
                    ),
                  ),
                  _SquareButton(
                    key: const Key('photoZoomIn'),
                    tooltip: 'Zoom in',
                    icon: Icons.zoom_in_rounded,
                    onPressed:
                        _zoom < _maxZoom - 0.001 ? () => _zoomBy(0.5) : null,
                  ),
                  const SizedBox(width: 12),
                  _SquareButton(
                    key: const Key('photoCropReset'),
                    tooltip: 'Fit the photo',
                    icon: Icons.fit_screen_rounded,
                    onPressed: () => _center(viewport),
                  ),
                ]),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: _editing
                      ? _toolbar()
                      : FilledButton(
                          key: const Key('photoCropConfirm'),
                          style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52)),
                          onPressed: _confirm,
                          child: Text(widget.confirmLabel),
                        ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  /// What the tool does, in a pill over the photo.
  Widget _hint() {
    final (icon, text) = switch (_tool) {
      _Tool.move => (
          Icons.open_with_rounded,
          'Drag to move · pinch or scroll to zoom'
        ),
      _Tool.draw => (Icons.brush_rounded, 'Draw on the photo'),
      _Tool.blur => (
          Icons.blur_on_rounded,
          'Paint over a face or a tattoo to blur it'
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: HuntrColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: HuntrColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: HuntrColors.orange),
          const SizedBox(width: 8),
          Flexible(
            child: Text(text,
                key: const Key('photoEditHint'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14)),
          ),
        ]),
      ),
    );
  }

  /// Move, Draw or Blur, Undo and Redo; Draw's colours, and the brush
  /// size for Draw and Blur.
  Widget _toolbar() {
    Widget tool(_Tool which, IconData icon, String label) {
      final on = _tool == which;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Material(
            color: on
                ? HuntrColors.orange.withValues(alpha: 0.18)
                : HuntrColors.surfaceHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                  color: on ? HuntrColors.orange : HuntrColors.border,
                  width: on ? 1.6 : 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: Key('photoTool-${which.name}'),
              onTap: () => setState(() => _tool = which),
              child: SizedBox(
                height: 72,
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon,
                          size: 26,
                          color: on ? HuntrColors.orange : Colors.white),
                      const SizedBox(height: 6),
                      Text(label,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: on ? HuntrColors.orange : Colors.white)),
                    ]),
              ),
            ),
          ),
        ),
      );
    }

    const label = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
    final size = _tool == _Tool.draw ? _drawSize : _blurSize;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          tool(_Tool.move, Icons.open_with_rounded, 'Move'),
          tool(_Tool.draw, Icons.brush_rounded, 'Draw'),
          tool(_Tool.blur, Icons.blur_on_rounded, 'Blur'),
          Container(
              width: 1,
              height: 48,
              margin: const EdgeInsets.only(right: 10),
              color: HuntrColors.border),
          Column(children: [
            _SquareButton(
              key: const Key('photoEditUndo'),
              tooltip: 'Undo',
              icon: Icons.undo_rounded,
              height: 34,
              onPressed: _strokes.isEmpty ? null : _undo,
            ),
            const SizedBox(height: 4),
            _SquareButton(
              key: const Key('photoEditRedo'),
              tooltip: 'Redo',
              icon: Icons.redo_rounded,
              height: 34,
              onPressed: _undone.isEmpty ? null : _redo,
            ),
          ]),
        ]),
        if (_tool == _Tool.draw) ...[
          const SizedBox(height: 18),
          const Text('Colour', style: label),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final color in _drawColors)
                Semantics(
                  button: true,
                  selected: color == _color,
                  label: 'Colour',
                  child: GestureDetector(
                    onTap: () => setState(() => _color = color),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: color == _color
                                ? HuntrColors.orange
                                : Colors.white24,
                            width: color == _color ? 3 : 1),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (_tool != _Tool.move) ...[
          const SizedBox(height: 18),
          Row(children: [
            const Expanded(child: Text('Brush size', style: label)),
            Text('${size.round()} px',
                key: const Key('photoBrushSizeLabel'),
                style: const TextStyle(color: HuntrColors.muted)),
          ]),
          Row(children: [
            Icon(
                _tool == _Tool.draw
                    ? Icons.brush_rounded
                    : Icons.blur_on_rounded,
                size: 20,
                color: HuntrColors.muted),
            Expanded(
              child: Slider(
                key: const Key('photoBrushSize'),
                value: size,
                min: _tool == _Tool.draw ? 3 : 14,
                max: _tool == _Tool.draw ? 30 : 90,
                onChanged: (v) => setState(() {
                  if (_tool == _Tool.draw) {
                    _drawSize = v;
                  } else {
                    _blurSize = v;
                  }
                }),
              ),
            ),
            // the brush as it paints
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: HuntrColors.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: HuntrColors.border),
              ),
              child: Container(
                width: math.min(size, 34),
                height: math.min(size, 34),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _tool == _Tool.draw
                      ? _color
                      : Colors.white.withValues(alpha: 0.35),
                  border: Border.all(color: Colors.white38),
                ),
              ),
            ),
          ]),
        ],
      ],
    );
  }
}

/// A small rounded square button (zoom, fit, undo, redo).
class _SquareButton extends StatelessWidget {
  const _SquareButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.height = 44,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    final on = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: HuntrColors.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: HuntrColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: height,
            child:
                Icon(icon, size: 22, color: on ? Colors.white : Colors.white38),
          ),
        ),
      ),
    );
  }
}

class _CropFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final frame =
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18));
    canvas.drawRRect(
        frame,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
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
