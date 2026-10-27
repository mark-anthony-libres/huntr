import 'package:flutter/material.dart';

import '../../theme.dart';

/// A HUNTR sticker's picture, from its link (stickers live on the server,
/// not in the app): nothing while it loads, its name if it can't.
class StickerImage extends StatelessWidget {
  const StickerImage(
      {super.key, required this.url, required this.name, this.size});

  final String? url;
  final String name;

  /// Width and height (null: as much as there's room for).
  final double? size;

  @override
  Widget build(BuildContext context) {
    final fallback = SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text('✨ $name',
            textAlign: TextAlign.center,
            style: const TextStyle(color: HuntrColors.muted, fontSize: 12)),
      ),
    );
    final link = url;
    if (link == null) return fallback;
    return Image.network(
      link,
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: '$name sticker',
      // a new link for the same picture (they're renewed daily) keeps the
      // old one on screen until it's in
      gaplessPlayback: true,
      frameBuilder: (_, child, frame, loaded) =>
          loaded || frame != null ? child : SizedBox(width: size, height: size),
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}
