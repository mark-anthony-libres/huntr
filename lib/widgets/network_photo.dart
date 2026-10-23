import 'package:flutter/material.dart';

import '../theme.dart';

/// A photo from a (temporary, presigned) link, with loading and error states.
///
/// On web the image falls back to a plain <img> element, which doesn't need
/// the bucket to allow cross-origin requests.
class NetworkPhoto extends StatelessWidget {
  const NetworkPhoto(this.url, {super.key, this.fit = BoxFit.cover});

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      // a new photo, a new image (the web's fallback <img> keeps the first)
      key: ValueKey(url),
      fit: fit,
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : const PhotoLoading(),
      errorBuilder: (context, error, stack) => const PhotoBroken(),
    );
  }
}

/// Shown while a photo loads.
class PhotoLoading extends StatelessWidget {
  const PhotoLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: HuntrColors.surfaceHigh,
      child: Center(
          child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2))),
    );
  }
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
