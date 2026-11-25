import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// What a stroke does: paints a colour, or blurs the photo under it.
enum PhotoStrokeKind { paint, blur }

/// One stroke drawn on a photo before it's uploaded (Draw or Blur in the
/// crop screen). Points and width are fractions of the photo (0-1, the
/// width as a fraction of the photo's width), so they fit the photo at any
/// size: on screen, and at full size when it's saved.
class PhotoStroke {
  PhotoStroke({
    required this.kind,
    required this.width,
    this.color = Colors.white,
    List<Offset>? points,
  }) : points = points ?? [];

  final PhotoStrokeKind kind;
  final double width;
  final Color color;
  final List<Offset> points;
}

/// How strong the blur is: its sigma as a fraction of the photo's width
/// (strong enough that what's under it can't be made out).
const _blurStrength = 0.025;

/// The blur strokes' area on a photo [size] big: round brush marks along
/// each stroke (their union).
Path blurArea(List<PhotoStroke> strokes, Size size) {
  final path = Path();
  for (final stroke in strokes) {
    if (stroke.kind != PhotoStrokeKind.blur || stroke.points.isEmpty) continue;
    final radius = stroke.width * size.width / 2;
    Offset at(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
    var last = at(stroke.points.first);
    path.addOval(Rect.fromCircle(center: last, radius: radius));
    for (final p in stroke.points.skip(1)) {
      final next = at(p);
      // marks close enough together to make a smooth band
      final steps = math.max(1, ((next - last).distance / (radius / 3)).ceil());
      for (var i = 1; i <= steps; i++) {
        final point = Offset.lerp(last, next, i / steps)!;
        path.addOval(Rect.fromCircle(center: point, radius: radius));
      }
      last = next;
    }
  }
  return path;
}

/// Draws the paint strokes on a canvas [size] big.
void paintStrokes(Canvas canvas, Size size, List<PhotoStroke> strokes) {
  for (final stroke in strokes) {
    if (stroke.kind != PhotoStrokeKind.paint || stroke.points.isEmpty) continue;
    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.width * size.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    Offset at(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
    if (stroke.points.length == 1) {
      canvas.drawCircle(at(stroke.points.first), paint.strokeWidth / 2,
          Paint()..color = stroke.color);
      continue;
    }
    final path = Path()
      ..moveTo(at(stroke.points.first).dx, at(stroke.points.first).dy);
    for (final p in stroke.points.skip(1)) {
      final point = at(p);
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }
}

/// The photo with its strokes, as the crop screen shows it ([image] laid
/// out [size] big): the blur over the photo, the paint over both.
class PhotoWithStrokes extends StatelessWidget {
  const PhotoWithStrokes({
    super.key,
    required this.image,
    required this.size,
    required this.strokes,
    required this.version,
  });

  final ImageProvider image;
  final Size size;
  final List<PhotoStroke> strokes;

  /// Changes whenever a stroke does (strokes grow in place while drawn).
  final int version;

  @override
  Widget build(BuildContext context) {
    final photo = Image(image: image, fit: BoxFit.fill);
    final blurring = strokes.any((s) => s.kind == PhotoStrokeKind.blur);
    return SizedBox.fromSize(
      size: size,
      child: Stack(fit: StackFit.expand, children: [
        photo,
        if (blurring)
          ClipPath(
            clipper: _BlurClip(strokes, version),
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                  sigmaX: size.width * _blurStrength,
                  sigmaY: size.width * _blurStrength,
                  tileMode: TileMode.clamp),
              child: photo,
            ),
          ),
        CustomPaint(painter: _PaintLayer(strokes, version)),
      ]),
    );
  }
}

class _BlurClip extends CustomClipper<Path> {
  _BlurClip(this.strokes, this.version);

  final List<PhotoStroke> strokes;
  final int version;

  @override
  Path getClip(Size size) => blurArea(strokes, size);

  @override
  bool shouldReclip(_BlurClip old) => old.version != version;
}

class _PaintLayer extends CustomPainter {
  _PaintLayer(this.strokes, this.version);

  final List<PhotoStroke> strokes;
  final int version;

  @override
  void paint(Canvas canvas, Size size) => paintStrokes(canvas, size, strokes);

  @override
  bool shouldRepaint(_PaintLayer old) => old.version != version;
}

/// The photo [bytes] with [strokes] baked in, as a PNG at most [maxSide]
/// pixels on its longest side (the original is never uploaded, so what's
/// blurred stays hidden).
Future<Uint8List> applyPhotoEdits(Uint8List bytes, List<PhotoStroke> strokes,
    {int maxSide = 2000}) async {
  final probe = await ui.instantiateImageCodec(bytes);
  final first = await probe.getNextFrame();
  final width = first.image.width, height = first.image.height;
  first.image.dispose();
  probe.dispose();
  final scale = math.min(1.0, maxSide / math.max(width, height));
  final codec = await ui.instantiateImageCodec(bytes,
      targetWidth: (width * scale).round(),
      targetHeight: (height * scale).round());
  final frame = await codec.getNextFrame();
  final photo = frame.image;
  codec.dispose();
  final size = Size(photo.width.toDouble(), photo.height.toDouble());

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImage(photo, Offset.zero, Paint());
  if (strokes.any((s) => s.kind == PhotoStrokeKind.blur)) {
    canvas
      ..save()
      ..clipPath(blurArea(strokes, size))
      ..drawImage(
          photo,
          Offset.zero,
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
                sigmaX: size.width * _blurStrength,
                sigmaY: size.width * _blurStrength,
                tileMode: TileMode.clamp))
      ..restore();
  }
  paintStrokes(canvas, size, strokes);
  final edited =
      await recorder.endRecording().toImage(photo.width, photo.height);
  photo.dispose();
  final png = await edited.toByteData(format: ui.ImageByteFormat.png);
  edited.dispose();
  return png!.buffer.asUint8List();
}
