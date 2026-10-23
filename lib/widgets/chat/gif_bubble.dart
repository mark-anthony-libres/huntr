import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../theme.dart';

/// A GIF in the chat, playing (from GIPHY's media servers), in a rounded
/// frame; a sticker shows on its own, without one.
class GifBubble extends StatelessWidget {
  const GifBubble({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final gif = message.gif!;
    final width = gif.isSticker
        ? 140.0
        : math.min(MediaQuery.sizeOf(context).width * 0.6, 220.0);
    final ratio = (gif.width / math.max(gif.height, 1)).clamp(0.5, 2.0);
    final image = SizedBox(
      width: width,
      height: width / ratio,
      child: GifImage(url: gif.url, fit: BoxFit.cover),
    );
    return Align(
      widthFactor: 1,
      alignment: message.fromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Semantics(
          image: true,
          label: gif.isSticker ? 'Sticker' : 'GIF',
          child: gif.isSticker
              ? image
              : ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child:
                      ColoredBox(color: HuntrColors.surfaceHigh, child: image),
                ),
        ),
      ),
    );
  }
}

/// A GIF or sticker image from GIPHY: a quiet placeholder while it loads,
/// and a note if it can't (e.g. GIPHY removed it).
class GifImage extends StatelessWidget {
  const GifImage({super.key, required this.url, this.fit = BoxFit.cover});

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Image.network(
        url,
        fit: fit,
        gaplessPlayback: true,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const ColoredBox(color: HuntrColors.surfaceHigh),
        errorBuilder: (context, error, stack) => const ColoredBox(
          color: HuntrColors.surfaceHigh,
          child: Center(
            child: Icon(Icons.gif_box_outlined, color: HuntrColors.muted),
          ),
        ),
      );
}
