import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../services/photo_cache/photo_cache_store.dart';
import '../../theme.dart';

/// A HUNTR sticker's picture, from its link (stickers live on the server,
/// not in the app): nothing while it loads, its name if it can't. Kept after
/// the first download: on phones in the app's cache folder (so it shows at
/// once, also after a restart and when its link is renewed), on the web by
/// the browser (the link stays the same for a day and says it never
/// changes).
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
        child: Text(name,
            textAlign: TextAlign.center,
            style: const TextStyle(color: HuntrColors.muted, fontSize: 12)),
      ),
    );
    final link = url;
    if (link == null) return fallback;
    Widget whileLoading(
            BuildContext _, Widget child, int? frame, bool loaded) =>
        loaded || frame != null ? child : SizedBox(width: size, height: size);
    if (kIsWeb) {
      return Image.network(
        link,
        width: size,
        height: size,
        fit: BoxFit.contain,
        semanticLabel: '$name sticker',
        // on the web, S3 (no CORS) only serves it to a plain <img>, as for photos
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        // a new link for the same picture (they're renewed daily) keeps the
        // old one on screen until it's in
        gaplessPlayback: true,
        frameBuilder: whileLoading,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    return Image(
      image: StickerPicture(link),
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: '$name sticker',
      gaplessPlayback: true,
      frameBuilder: whileLoading,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

/// A sticker's picture on a phone: the same picture whatever its (signed,
/// renewed) link, so it's one image in memory and one file on the device,
/// downloaded once. A new picture for a sticker has a new S3 path, so it's
/// a new file (fetched once too).
@immutable
class StickerPicture extends ImageProvider<StickerPicture> {
  StickerPicture(this.url) : path = url.split('?').first;

  final String url;

  /// The picture's S3 path: what it's known by.
  final String path;

  static final PhotoCacheStore _store = PhotoCacheStore.device('stickers');
  static final http.Client _client = http.Client();

  @override
  Future<StickerPicture> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
          StickerPicture key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
          codec: _codec(decode), scale: 1, debugLabel: path);

  Future<ui.Codec> _codec(ImageDecoderCallback decode) async =>
      decode(await ui.ImmutableBuffer.fromUint8List(await _bytes()));

  Future<Uint8List> _bytes() async {
    final file = _fileId(path);
    try {
      final saved = await _store.read(file);
      if (saved != null) return saved;
    } catch (_) {
      // no cache folder: just download it
    }
    final uri = Uri.parse(url);
    final response = await _client.get(uri);
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw NetworkImageLoadException(
          statusCode: response.statusCode, uri: uri);
    }
    try {
      await _store.write(file, response.bodyBytes);
    } catch (_) {
      // shown anyway; downloaded again next time
    }
    return response.bodyBytes;
  }

  /// The file's number for a path: the same on every run (FNV-1a).
  static int _fileId(String path) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(path)) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  @override
  bool operator ==(Object other) =>
      other is StickerPicture && other.path == path;

  @override
  int get hashCode => path.hashCode;
}
