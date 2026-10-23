import 'package:flutter/material.dart';

const double brandMarkSize = 30;

class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/google_g_logo.png',
      key: const Key('googleLogo'),
      width: brandMarkSize,
      height: brandMarkSize,
      semanticLabel: 'Google logo',
    );
  }
}

class FacebookMark extends StatelessWidget {
  const FacebookMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Facebook logo',
      child: const ExcludeSemantics(
        child: SizedBox(
          key: Key('facebookLogo'),
          width: brandMarkSize,
          height: brandMarkSize,
          child: CustomPaint(painter: _FacebookLogoPainter()),
        ),
      ),
    );
  }
}

/// Blue circle with the white "f", drawn on a 1024 x 1024 grid.
class _FacebookLogoPainter extends CustomPainter {
  const _FacebookLogoPainter();

  static const _grid = 1024.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _grid, size.height / _grid);
    canvas.drawCircle(
      const Offset(_grid / 2, _grid / 2),
      _grid / 2,
      Paint()..color = const Color(0xFF1877F2),
    );
    final f = Path()
      ..moveTo(711.3, 660)
      ..lineTo(734, 512)
      ..lineTo(592, 512)
      ..lineTo(592, 416)
      ..cubicTo(592, 375.47, 611.84, 336, 675.44, 336)
      ..lineTo(740, 336)
      ..lineTo(740, 210)
      ..cubicTo(740, 210, 681.41, 200, 625.39, 200)
      ..cubicTo(508.44, 200, 432, 270.88, 432, 399.2)
      ..lineTo(432, 512)
      ..lineTo(302, 512)
      ..lineTo(302, 660)
      ..lineTo(432, 660)
      ..lineTo(432, 1017.78)
      ..arcToPoint(const Offset(592, 1017.78),
          radius: const Radius.circular(517.396), clockwise: false)
      ..lineTo(592, 660)
      ..close();
    canvas.drawPath(f, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_FacebookLogoPainter oldDelegate) => false;
}
