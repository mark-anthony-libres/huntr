import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../avatar.dart';
import '../network_photo.dart';
import '../photo.dart';
import '../photos/viewer_controls.dart';

class _PhotoGalleryState extends State<PhotoGallery> {
  int _page = 0;
  late final PageController _pages = widget.controller ?? PageController();

  @override
  void dispose() {
    if (widget.controller == null) _pages.dispose();
    super.dispose();
  }

  void _go(int delta, int count) {
    final next = (_page + delta).clamp(0, count - 1);
    if (next != _page) {
      _pages.animateToPage(next,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final urls = p.photoUrls;
    final count = urls.isNotEmpty
        ? urls.length
        : p.photos.isEmpty
            ? 1
            : p.photos.length;
    return Stack(fit: StackFit.expand, children: [
      // swipe with touch, mouse or trackpad
      SwipeAnyDevice(
          child: PageView.builder(
        controller: _pages,
        itemCount: count,
        onPageChanged: (i) {
          setState(() => _page = i);
          widget.onPageChanged?.call(i);
        },
        itemBuilder: (_, i) => urls.isNotEmpty
            ? NetworkPhoto(urls[i])
            : i == 0 && (widget.firstIsAvatar || p.photos.isEmpty)
                ? Hero(
                    tag: 'art-${p.id}',
                    child: ProfileArt(profile: p, fontSize: 110))
                : PhotoArt(photo: p.photos[i], radius: 0, iconSize: 96),
      )),
      // tap the left or right side to move between photos
      if (count > 1)
        Positioned.fill(
          child: Row(children: [
            Expanded(
                child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _go(-1, count))),
            Expanded(
                child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _go(1, count))),
          ]),
        ),
      // previous / next arrows (hidden at the ends)
      if (count > 1 && _page > 0)
        Align(
          alignment: Alignment.centerLeft,
          child: ArrowButton(
              key: const Key('galleryPrevious'),
              icon: Icons.chevron_left,
              tooltip: 'Previous photo',
              onPressed: () => _go(-1, count)),
        ),
      if (count > 1 && _page < count - 1)
        Align(
          alignment: Alignment.centerRight,
          child: ArrowButton(
              key: const Key('galleryNext'),
              icon: Icons.chevron_right,
              tooltip: 'Next photo',
              onPressed: () => _go(1, count)),
        ),
      // which photo, of how many
      if (count > 1)
        Positioned(
          left: 14,
          bottom: 14,
          child: IgnorePointer(
            child: Container(
              key: const Key('galleryCounter'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.photo_outlined, size: 17, color: Colors.white),
                const SizedBox(width: 7),
                Text('${_page + 1} / $count',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      if (count > 1)
        Positioned(
          left: 16,
          right: 16,
          top: MediaQuery.paddingOf(context).top + 6,
          child: IgnorePointer(
            child: Row(children: [
              for (var i = 0; i < count; i++)
                Expanded(
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: Colors.white
                          .withValues(alpha: i == _page ? 0.95 : 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ]),
          ),
        ),
    ]);
  }
}

/// Swipeable public profile pictures with a page indicator.
class PhotoGallery extends StatefulWidget {
  const PhotoGallery(
      {super.key,
      required this.profile,
      this.firstIsAvatar = true,
      this.controller,
      this.onPageChanged});
  final Profile profile;

  /// Moves it from outside (e.g. a strip of thumbnails); its own otherwise.
  final PageController? controller;
  final ValueChanged<int>? onPageChanged;

  /// Other people's first page is their generated avatar; your own preview
  /// shows your real main photo instead.
  final bool firstIsAvatar;

  @override
  State<PhotoGallery> createState() => _PhotoGalleryState();
}
