import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../models/models.dart';
import '../photo.dart';
import '../photos/viewer_controls.dart';

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController _pages =
      PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int index) => _pages.animateToPage(index,
      duration: const Duration(milliseconds: 250), curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    final count = widget.photos.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('${_index + 1} of $count'),
      ),
      body: Stack(children: [
        // swipe with touch, mouse or trackpad
        SwipeAnyDevice(child: _pageView()),
        if (count > 1) ...[
          if (_index > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: ArrowButton(
                  icon: Icons.chevron_left,
                  tooltip: 'Previous',
                  onPressed: () => _goTo(_index - 1)),
            ),
          if (_index < count - 1)
            Align(
              alignment: Alignment.centerRight,
              child: ArrowButton(
                  icon: Icons.chevron_right,
                  tooltip: 'Next',
                  onPressed: () => _goTo(_index + 1)),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: PageDots(count: count, current: _index),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _pageView() => PageView.builder(
        key: const Key('albumViewerPages'),
        controller: _pages,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) {
          final photo = widget.photos[i];
          final video = photo.stored?.isVideo == true ? photo.stored : null;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: video != null
                  // only the page on screen plays
                  ? _VideoPage(
                      key: ValueKey(video.id),
                      video: video,
                      active: i == _index)
                  : AspectRatio(
                      aspectRatio: photo.stored == null
                          ? 3 / 4
                          : photo.stored!.width / photo.stored!.height,
                      child: Hero(
                        tag: 'photo-${photo.id}',
                        child: PhotoArt(
                            photo: photo,
                            radius: 20,
                            iconSize: 72,
                            showLabel: true),
                      ),
                    ),
            ),
          );
        },
      );
}

class PhotoViewer extends StatefulWidget {
  const PhotoViewer(
      {super.key,
      required this.photos,
      required this.initial,
      required this.title});
  final List<AlbumPhoto> photos;
  final int initial;
  final String title;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

/// One of my album videos, streamed from its (temporary) link: tap to play
/// or pause. Shows its thumbnail until it's ready.
class _VideoPage extends StatefulWidget {
  const _VideoPage({super.key, required this.video, required this.active});
  final StoredAlbumItem video;
  final bool active;

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  late final VideoPlayerController _player =
      VideoPlayerController.networkUrl(Uri.parse(widget.video.url));
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _player.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      if (widget.active) _player.play();
    }, onError: (Object _) {
      if (mounted) setState(() => _failed = true);
    });
    _player.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(_VideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) _player.pause();
  }

  @override
  void dispose() {
    _player.removeListener(_changed);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = widget.video.width / widget.video.height;
    if (_failed) {
      return const Text('This video could not be played.',
          style: TextStyle(color: Colors.white70));
    }
    if (!_ready) {
      return AspectRatio(
        aspectRatio: ratio,
        child: PhotoArt(photo: AlbumPhoto.stored(widget.video), radius: 20),
      );
    }
    final playing = _player.value.isPlaying;
    return GestureDetector(
      key: const Key('albumVideo'),
      onTap: () => playing ? _player.pause() : _player.play(),
      child: AspectRatio(
        aspectRatio: _player.value.aspectRatio,
        child: Stack(fit: StackFit.expand, children: [
          ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: VideoPlayer(_player)),
          if (!playing)
            const Center(
              child: Icon(Icons.play_circle_fill_rounded,
                  size: 72, color: Colors.white70, semanticLabel: 'Play'),
            ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 8,
            child: VideoProgressIndicator(_player, allowScrubbing: true),
          ),
        ]),
      ),
    );
  }
}
