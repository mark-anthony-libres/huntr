import 'package:flutter/material.dart';

import '../theme.dart';

/// HUNTR's loading animation, the same as the web page shows before the
/// app starts (web/index.html), so one hands over to the other: the logo
/// builds itself (left leg drops in, right leg rises, the crossbar draws
/// across, a light sweeps over the H) and comes apart; then "huntr" comes
/// in letter by letter, as on the Me screen, and lifts away; and again.
/// Just the logo, still, when the device asks for less motion.
class HuntrLoader extends StatefulWidget {
  const HuntrLoader({super.key, this.size = 160});

  /// The logo's square; the text is sized to match.
  final double size;

  @override
  State<HuntrLoader> createState() => _HuntrLoaderState();
}

class _HuntrLoaderState extends State<HuntrLoader>
    with SingleTickerProviderStateMixin {
  static const _brand = 'huntr';
  static const _mark = 'assets/huntr_mark.png';

  // where the icon's legs end and the crossbar runs (fractions of its width)
  static const _leftEnd = 0.398, _barStart = 0.396, _barEnd = 0.606;
  static const _rightStart = 0.6055;

  static const _arrive = Cubic(.2, .9, .3, 1.15);
  static const _leave = Cubic(.6, 0, .8, .4);
  static const _draw = Cubic(.5, 0, .3, 1);

  late final _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 5200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// How far through [from]..[to] the cycle is, 0 to 1.
  static double _part(double t, double from, double to) =>
      ((t - from) / (to - from)).clamp(0.0, 1.0);

  /// A leg: in from [enter] (a fraction of the height), out to [exit].
  static double _legY(double t, double inFrom, double inTo, double outFrom,
      double outTo, double enter, double exit) {
    if (t < outFrom) return enter * (1 - _arrive.transform(_part(t, inFrom, inTo)));
    return exit * _leave.transform(_part(t, outFrom, outTo));
  }

  Widget _slice(double left, double right, double dy) {
    final size = widget.size;
    return Transform.translate(
      offset: Offset(0, dy * size),
      child: ClipRect(
        clipper: _Slice(left, right),
        child: Image.asset(_mark, width: size, height: size),
      ),
    );
  }

  Widget _logo(double t) {
    final size = widget.size;
    final barRight =
        _barStart + (_barEnd - _barStart) * _draw.transform(_part(t, 0.08, 0.15));
    final barLeft =
        _barStart + (_barEnd - _barStart) * _draw.transform(_part(t, 0.34, 0.40));
    // the light, from beyond the left edge to beyond the right
    final shine = -0.4 + 1.8 * Curves.easeInOut.transform(_part(t, 0.17, 0.30));
    final pieces = Stack(children: [
      _slice(0, _leftEnd, _legY(t, 0, 0.09, 0.38, 0.46, -1.1, 1.1)),
      _slice(_rightStart, 1, _legY(t, 0.02, 0.11, 0.39, 0.47, 1.1, -1.1)),
      if (barRight > barLeft) _slice(barLeft, barRight, 0),
    ]);
    return ClipRect(
      child: SizedBox.square(
        dimension: size,
        child: t < 0.17 || t > 0.30
            ? pieces
            // over the H only: the shader paints where the pieces are
            : ShaderMask(
                blendMode: BlendMode.srcATop,
                shaderCallback: (rect) => LinearGradient(
                  begin: const Alignment(-1, -0.25),
                  end: const Alignment(1, 0.25),
                  colors: const [
                    Color(0x00FFECD6),
                    Color(0xBFFFECD6),
                    Color(0x00FFECD6),
                  ],
                  stops: [shine - 0.15, shine, shine + 0.15],
                ).createShader(rect),
                child: pieces,
              ),
      ),
    );
  }

  Widget _text(double t) {
    final style = TextStyle(
      fontSize: widget.size * 0.4,
      fontWeight: FontWeight.w800,
      height: 1,
      color: Colors.white,
    );
    final out = Curves.easeIn.transform(_part(t, 0.88, 0.97));
    return Opacity(
      opacity: 1 - out,
      child: Transform.translate(
        offset: Offset(0, -20 * out),
        child: ShaderMask(
          shaderCallback: HuntrColors.accentGradient.createShader,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final (i, letter) in _brand.split('').indexed)
              Builder(builder: (context) {
                // each letter a little after the one before
                final start = 0.5 + i * 0.023;
                final shown = Curves.easeOutBack
                    .transform(_part(t, start, start + 0.08));
                return Opacity(
                  opacity: shown.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, 24 * (1 - shown)),
                    child: Transform.scale(
                        scale: 0.6 + 0.4 * shown,
                        child: Text(letter, style: style)),
                  ),
                );
              }),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading HUNTR',
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            if (!_controller.isAnimating) {
              return Image.asset(_mark,
                  width: widget.size, height: widget.size);
            }
            final t = _controller.value;
            // the logo's height throughout; as wide as the word needs
            return ConstrainedBox(
              constraints: BoxConstraints(
                  minWidth: widget.size,
                  minHeight: widget.size,
                  maxHeight: widget.size),
              child: Center(
                  widthFactor: 1,
                  child: t < 0.5 ? _logo(t) : _text(t)),
            );
          },
        ),
      ),
    );
  }
}

/// The part of the icon between two fractions of its width.
class _Slice extends CustomClipper<Rect> {
  const _Slice(this.left, this.right);

  final double left;
  final double right;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(size.width * left, 0, size.width * right, size.height);

  @override
  bool shouldReclip(_Slice old) => old.left != left || old.right != right;
}
