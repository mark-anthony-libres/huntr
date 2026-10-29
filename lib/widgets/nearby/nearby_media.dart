import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../services/huntr_backend.dart';

/// "0:42", "1:05:09".
String mediaDurationLabel(Duration d) {
  String pad(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h:${pad(m)}:${pad(s)}' : '$m:${pad(s)}';
}

Widget _picture(String url, {BoxFit fit = BoxFit.cover, Key? key}) => Image
    .network(url,
        key: key,
        fit: fit,
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        loadingBuilder: (context, child, progress) =>
            progress ==
                    null
                ? child
                : const ColoredBox(color: Color(0xFF1A1B20)),
        errorBuilder: (context, error, stack) => const ColoredBox(
            color: Color(0xFF1A1B20),
            child: Center(
                child:
                    Icon(Icons.broken_image_outlined, color: Colors.white38))));

/// One square of the grid: the still, a play mark and length on videos,
/// "+N" over the last when there are more.
class _Tile extends StatelessWidget {
  const _Tile(
      {required this.media,
      required this.onTap,
      this.more = 0,
      this.whole = false});

  final NearbyMedia media;
  final VoidCallback onTap;
  final int more;

  /// Shown whole (not cropped), on a blurred copy of itself: a tall one in
  /// a square.
  final bool whole;

  @override
  Widget build(BuildContext context) => GestureDetector(
        key: Key('nearbyMedia-${media.id}'),
        onTap: onTap,
        child: Stack(fit: StackFit.expand, children: [
          if (whole) ...[
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: _picture(media.previewUrl),
            ),
            const ColoredBox(color: Color(0x66000000)),
            _picture(media.previewUrl, fit: BoxFit.contain),
          ] else
            _picture(media.previewUrl),
          if (media.isVideo) ...[
            const Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                    color: Colors.black54, shape: BoxShape.circle),
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 30),
                ),
              ),
            ),
            if (media.duration != null)
              Positioned(
                left: 6,
                bottom: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(4)),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(mediaDurationLabel(media.duration!),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
          ],
          if (more > 0)
            ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Text('+$more',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800)),
              ),
            ),
        ]),
      );
}

/// The tallest the photos and videos of a post are in the feed, however
/// wide the screen (on a computer, a square would be as tall as the page).
const nearbyMediaMaxHeight = 440.0;

/// [aspectRatio] (width / height) across the full width, but never taller
/// than [nearbyMediaMaxHeight].
class _Frame extends StatelessWidget {
  const _Frame({required this.aspectRatio, required this.child});

  final double aspectRatio;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => SizedBox(
          width: box.maxWidth,
          height: (box.maxWidth / aspectRatio).clamp(0.0, nearbyMediaMaxHeight),
          child: child,
        ),
      );
}

/// An official post's photos and videos as a grid: one in its own shape;
/// two side by side; three as one tall and two; four or more as a 2 x 2
/// with "+N" on the last. A tap opens them full size.
class NearbyMediaGrid extends StatelessWidget {
  const NearbyMediaGrid({super.key, required this.media});

  final List<NearbyMedia> media;

  void _open(BuildContext context, int index) =>
      Navigator.of(context).push(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => NearbyMediaViewer(media: media, start: index)));

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) return const SizedBox.shrink();
    Widget tile(int i, {int more = 0, bool whole = false}) => _Tile(
        media: media[i],
        more: more,
        whole: whole,
        onTap: () => _open(context, i));
    const gap = SizedBox.square(dimension: 2);
    final Widget grid;
    if (media.length == 1) {
      // wide ones in their own shape (up to 2:1); tall ones (a phone's
      // video) whole in a square, so they don't take over the feed
      final ratio = media.first.aspectRatio;
      grid = _Frame(
          aspectRatio: ratio < 1 ? 1 : ratio.clamp(1.0, 2.0),
          child: tile(0, whole: ratio < 1));
    } else if (media.length == 2) {
      grid = _Frame(
          aspectRatio: 16 / 10,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: tile(0)),
            gap,
            Expanded(child: tile(1)),
          ]));
    } else if (media.length == 3) {
      grid = _Frame(
          aspectRatio: 16 / 10,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: tile(0)),
            gap,
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Expanded(child: tile(1)),
                  gap,
                  Expanded(child: tile(2)),
                ])),
          ]));
    } else {
      Widget row(int a, int b, {int more = 0}) => Expanded(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: tile(a)),
              gap,
              Expanded(child: tile(b, more: more)),
            ]),
          );
      grid = _Frame(
          aspectRatio: 16 / 10,
          child: Column(children: [
            row(0, 1),
            gap,
            row(2, 3, more: media.length - 4),
          ]));
    }
    return ClipRRect(borderRadius: BorderRadius.circular(16), child: grid);
  }
}

/// Photos and videos full size, swiped one to the next: photos zoom,
/// videos play (a tap pauses).
class NearbyMediaViewer extends StatefulWidget {
  const NearbyMediaViewer({super.key, required this.media, this.start = 0});

  final List<NearbyMedia> media;
  final int start;

  @override
  State<NearbyMediaViewer> createState() => _NearbyMediaViewerState();
}

class _NearbyMediaViewerState extends State<NearbyMediaViewer> {
  late final PageController _pages = PageController(initialPage: widget.start);
  late int _index = widget.start;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.media.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: count > 1 ? Text('${_index + 1} / $count') : null,
      ),
      body: SafeArea(
        child: PageView.builder(
          controller: _pages,
          itemCount: count,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (context, i) {
            final media = widget.media[i];
            return media.isVideo
                // only the one on screen plays
                ? _Video(media: media, active: i == _index)
                : InteractiveViewer(
                    maxScale: 5,
                    child: Center(
                        child: _picture(media.url,
                            fit: BoxFit.contain,
                            key: Key('nearbyMediaFull-${media.id}'))),
                  );
          },
        ),
      ),
    );
  }
}

class _Video extends StatefulWidget {
  const _Video({required this.media, required this.active});

  final NearbyMedia media;
  final bool active;

  @override
  State<_Video> createState() => _VideoState();
}

class _VideoState extends State<_Video> {
  late final VideoPlayerController _player =
      VideoPlayerController.networkUrl(Uri.parse(widget.media.url));
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _player.addListener(_changed);
    _player.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      if (widget.active) _player.play();
    }, onError: (Object _) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void didUpdateWidget(_Video old) {
    super.didUpdateWidget(old);
    if (!_player.value.isInitialized) return;
    if (widget.active && !old.active) _player.play();
    if (!widget.active) _player.pause();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _player.removeListener(_changed);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(
          child: Text('This video could not be played.',
              style: TextStyle(color: Colors.white70)));
    }
    if (!_player.value.isInitialized) {
      return Stack(fit: StackFit.expand, children: [
        Center(
          child: AspectRatio(
              aspectRatio: widget.media.aspectRatio,
              child: _picture(widget.media.previewUrl, fit: BoxFit.contain)),
        ),
        const Center(child: CircularProgressIndicator()),
      ]);
    }
    return GestureDetector(
      key: Key('nearbyMediaVideo-${widget.media.id}'),
      onTap: () => _player.value.isPlaying ? _player.pause() : _player.play(),
      child: Center(
        child: AspectRatio(
          aspectRatio: _player.value.aspectRatio,
          child: Stack(fit: StackFit.expand, children: [
            VideoPlayer(_player),
            if (!_player.value.isPlaying)
              const Center(
                  child: Icon(Icons.play_circle_fill_rounded,
                      size: 72, color: Colors.white70)),
            Positioned(
              left: 12,
              right: 12,
              bottom: 8,
              child: VideoProgressIndicator(_player, allowScrubbing: true),
            ),
          ]),
        ),
      ),
    );
  }
}
