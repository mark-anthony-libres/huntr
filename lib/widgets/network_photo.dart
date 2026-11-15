import 'package:flutter/material.dart';

import '../theme.dart';

/// A photo from a (temporary, presigned) link, with loading and error states.
///
/// On web the image falls back to a plain <img> element, which doesn't need
/// the bucket to allow cross-origin requests.
class NetworkPhoto extends StatelessWidget {
  const NetworkPhoto(this.url,
      {super.key, this.fit = BoxFit.cover, this.broken});

  final String url;
  final BoxFit fit;

  /// Shown when it can't be loaded (none: [PhotoBroken]).
  final Widget? broken;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      // a new photo, a new image (the web's fallback <img> keeps the first)
      key: ValueKey(url),
      fit: fit,
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      // the shimmer until there's something to show (also before any
      // bytes arrive, which a loading builder doesn't cover)
      frameBuilder: (context, child, frame, synchronous) =>
          frame == null && !synchronous ? const PhotoLoading() : child,
      errorBuilder: (context, error, stack) => broken ?? const PhotoBroken(),
    );
  }
}

/// Shown while a photo loads: a soft light sweeping across (as on
/// Facebook); still when the device asks for less motion.
class PhotoLoading extends StatefulWidget {
  const PhotoLoading({super.key});

  @override
  State<PhotoLoading> createState() => _PhotoLoadingState();
}

class _PhotoLoadingState extends State<PhotoLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1300));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const base = HuntrColors.surfaceHigh;
    final light = Color.lerp(base, Colors.white, 0.07)!;
    return AnimatedBuilder(
      key: const Key('photoLoading'),
      animation: _sweep,
      builder: (context, _) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [base, light, base],
            stops: const [0.35, 0.5, 0.65],
            transform: _Slide(_sweep.value),
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Moves the sweep from off one side ([t] 0) to off the other ([t] 1).
class _Slide extends GradientTransform {
  const _Slide(this.t);

  final double t;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (2 * t - 1), 0, 0);
}

/// Shown when a photo can't be loaded.
class PhotoBroken extends StatelessWidget {
  const PhotoBroken({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: HuntrColors.surfaceHigh,
      child: Center(
          child: Icon(Icons.broken_image_outlined, color: HuntrColors.muted)),
    );
  }
}
