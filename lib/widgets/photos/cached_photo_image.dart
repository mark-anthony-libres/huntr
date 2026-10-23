import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/photo_cache/photo_cache.dart';
import '../../services/services_scope.dart';
import '../network_photo.dart';

/// One of my stored pictures (a profile photo, or an album photo or video
/// thumbnail), from the device cache of its [collection] when it's saved
/// there, otherwise downloaded once and saved. Without a cache (or when
/// loading fails) it falls back to [NetworkPhoto].
///
/// In debug builds a small grey dot marks a photo whose shown bytes were
/// read from the device cache.
class CachedPhotoImage extends StatefulWidget {
  const CachedPhotoImage(this.photo,
      {super.key,
      this.fit = BoxFit.cover,
      this.collection = PhotoCollection.profile});

  final StoredPhoto photo;
  final BoxFit fit;
  final PhotoCollection collection;

  @override
  State<CachedPhotoImage> createState() => _CachedPhotoImageState();
}

class _CachedPhotoImageState extends State<CachedPhotoImage> {
  PhotoCache? _cache;
  int? _photoId;
  CachedPhoto? _photo;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cache = ServicesScope.photoCacheOf(context, widget.collection);
    if (_photoId != widget.photo.id) _start();
  }

  @override
  void didUpdateWidget(CachedPhotoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo.id != widget.photo.id) _start();
  }

  void _start() {
    final cache = _cache;
    final photoId = widget.photo.id;
    _photoId = photoId;
    _failed = false;
    _photo = cache?.peek(photoId);
    if (cache == null || _photo != null) return;
    cache.load(widget.photo).then((photo) {
      // Ignore a load for a photo no longer shown here.
      if (!mounted || _photoId != photoId) return;
      setState(() {
        _photo = photo;
        _failed = photo == null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cache == null || _failed) {
      return NetworkPhoto(widget.photo.imageUrl, fit: widget.fit);
    }
    final photo = _photo;
    if (photo == null) return const PhotoLoading();
    return Image.memory(
      photo.bytes,
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) => const PhotoBroken(),
      frameBuilder: (context, child, frame, synchronous) {
        if (frame == null) return const PhotoLoading();
        if (!kDebugMode || photo.source != PhotoSource.deviceCache) {
          return child;
        }
        return Stack(fit: StackFit.expand, children: [
          child,
          // bottom-right: clear of the tiles' remove buttons (top-right)
          const Positioned(bottom: 6, right: 6, child: _CachedDot()),
        ]);
      },
    );
  }
}

/// Debug only: this photo was shown from the device cache. Grey, since
/// green means "online" in Huntr.
class _CachedDot extends StatelessWidget {
  const _CachedDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('photoCachedDot'),
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey.shade400,
        border: Border.all(color: Colors.black54, width: 1.5),
      ),
    );
  }
}
