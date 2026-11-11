import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../avatar.dart';
import '../network_photo.dart';
import '../photo.dart';
import '../photos/viewer_controls.dart';

class _PhotoGalleryState extends State<PhotoGallery> {
  int _page = 0;
  late final PageController _pages = widget.controller ?? PageController();

  /// [PhotoGallery.autoPlay]: the next photo every few seconds, until the
  /// gallery is touched (then it's theirs to move).
  Timer? _carousel;
  static const _carouselEvery = Duration(seconds: 4);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final count = widget.profile.photoUrls.length;
    // not when the device asks for less motion
    if (widget.autoPlay &&
        count > 1 &&
        _carousel == null &&
        !MediaQuery.disableAnimationsOf(context)) {
      _carousel = Timer.periodic(_carouselEvery, (_) {
        if (!_pages.hasClients) return;
        final next = (_page + 1) % count;
        _pages.animateToPage(next,
            duration: Duration(milliseconds: next == 0 ? 450 : 350),
            curve: Curves.easeInOut);
      });
    }
  }

  void _stopCarousel() {
    _carousel?.cancel();
  }

  @override
  void dispose() {
    _carousel?.cancel();
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
    final albums = widget.showAlbums ? p.albumsToTrade : 0;
    return Listener(
      // touched: the carousel stops
      onPointerDown: (_) => _stopCarousel(),
      child: Stack(fit: StackFit.expand, children: [
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
        // a tap opens the photo full screen (when it can be); otherwise the
        // left or right side moves between photos
        if (widget.onOpen case final open? when urls.isNotEmpty)
          Positioned.fill(
            child: GestureDetector(
                key: const Key('galleryOpen'),
                behavior: HitTestBehavior.translucent,
                onTap: () => open(_page)),
          )
        else if (count > 1)
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.photo_outlined,
                      size: 17, color: Colors.white),
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
        if (albums > 0)
          Positioned(
            right: 14,
            bottom: 14,
            child: IgnorePointer(
              child: Container(
                key: const Key('galleryAlbums'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.photo_library_outlined,
                      size: 17, color: Colors.white),
                  const SizedBox(width: 7),
                  Text(albums == 1 ? '1 album' : '$albums albums',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Swipeable public profile pictures with a page indicator.
class PhotoGallery extends StatefulWidget {
  const PhotoGallery(
      {super.key,
      required this.profile,
      this.firstIsAvatar = true,
      this.controller,
      this.onPageChanged,
      this.onOpen,
      this.autoPlay = false,
      this.showAlbums = false});

  /// Moves to the next photo by itself every few seconds (a carousel),
  /// until it's touched.
  final bool autoPlay;

  /// Says how many albums they have (to trade for), on the photo.
  final bool showAlbums;
  final Profile profile;

  /// A tap on a photo: open it (this one) full screen.
  final ValueChanged<int>? onOpen;

  /// Moves it from outside (e.g. a strip of thumbnails); its own otherwise.
  final PageController? controller;
  final ValueChanged<int>? onPageChanged;

  /// Other people's first page is their generated avatar; your own preview
  /// shows your real main photo instead.
  final bool firstIsAvatar;

  @override
  State<PhotoGallery> createState() => _PhotoGalleryState();
}
