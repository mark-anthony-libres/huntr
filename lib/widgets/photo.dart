import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/photo_cache/photo_cache.dart';
import '../theme.dart';
import 'photos/cached_photo_image.dart';

/// Placeholder picture for an album photo: a soft gradient "scene" with the subject's icon.
class PhotoArt extends StatelessWidget {
  const PhotoArt(
      {super.key,
      required this.photo,
      this.radius = 12,
      this.iconSize = 34,
      this.showLabel = false});

  final AlbumPhoto photo;
  final double radius;
  final double iconSize;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final stored = photo.stored;
    if (stored != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(fit: StackFit.expand, children: [
          CachedPhotoImage(stored, collection: PhotoCollection.album),
          if (stored.isVideo) VideoBadge(durationMs: stored.durationMs),
        ]),
      );
    }
    final a = HSLColor.fromAHSL(1, photo.hue, 0.5, 0.5).toColor();
    final b =
        HSLColor.fromAHSL(1, (photo.hue + 60) % 360, 0.55, 0.24).toColor();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [a, b],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: -20,
              bottom: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    shape: BoxShape.circle),
              ),
            ),
            Center(
                child: Icon(photo.subject.icon,
                    size: iconSize,
                    color: Colors.white.withValues(alpha: 0.85))),
            if (showLabel)
              Positioned(
                left: 10,
                bottom: 8,
                child: Text(photo.subject.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(blurRadius: 6)])),
              ),
          ],
        ),
      ),
    );
  }
}

/// Marks a video: a play icon, and its length in the corner.
class VideoBadge extends StatelessWidget {
  const VideoBadge({super.key, required this.durationMs});
  final int? durationMs;

  @override
  Widget build(BuildContext context) {
    final seconds = ((durationMs ?? 0) / 1000).round();
    return Stack(fit: StackFit.expand, children: [
      Center(
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: const BoxDecoration(
              color: Colors.black54, shape: BoxShape.circle),
          child: const Icon(Icons.play_arrow_rounded,
              color: Colors.white, semanticLabel: 'Video'),
        ),
      ),
      if (durationMs != null)
        Positioned(
          left: 8,
          bottom: 6,
          child: Text(
              '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 4)])),
        ),
    ]);
  }
}

/// A small preview grid of an album. When [locked], the photos are blurred behind a lock.
class AlbumPreview extends StatelessWidget {
  const AlbumPreview(
      {super.key,
      required this.photos,
      this.locked = false,
      this.onTap,
      this.maxTiles = 4});

  final List<AlbumPhoto> photos;
  final bool locked;
  final VoidCallback? onTap;
  final int maxTiles;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return const Text('No photos yet',
          style: TextStyle(color: HuntrColors.muted));
    }
    final shown = photos.take(maxTiles).toList();
    final extra = photos.length - shown.length;
    final grid = Row(
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(fit: StackFit.expand, children: [
                PhotoArt(photo: shown[i], iconSize: 24),
                if (i == shown.length - 1 && extra > 0)
                  Container(
                    decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.center,
                    child: Text('+$extra',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
          ),
        ],
        for (var i = shown.length; i < maxTiles; i++) ...[
          const SizedBox(width: 6),
          const Expanded(child: SizedBox()),
        ],
      ],
    );
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: locked
          ? Stack(children: [
              ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                  child: grid),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.lock_outline, size: 18),
                    SizedBox(width: 6),
                    Text('Private',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ])
          : grid,
    );
  }
}
