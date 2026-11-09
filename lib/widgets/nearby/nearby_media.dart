import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../flows/chat_attachments.dart' show ChatMediaPicker;
import '../../services/huntr_backend.dart';
import '../../services/nearby_service.dart';
import '../../services/nearby_uploads.dart';
import '../../services/services_scope.dart';
import '../../state/app_state.dart';

/// "0:42", "1:05:09".
String mediaDurationLabel(Duration d) {
  String pad(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h:${pad(m)}:${pad(s)}' : '$m:${pad(s)}';
}

/// The still at [url]; none yet (a member's file on its way): a dark box.
Widget _picture(String? url, {BoxFit fit = BoxFit.cover, Key? key}) => url ==
        null
    ? const ColoredBox(color: Color(0xFF1A1B20))
    : Image.network(url,
        key: key,
        fit: fit,
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        loadingBuilder: (context, child, progress) => progress == null
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

  /// Shown whole (not cropped), on black: a tall one in a square.
  final bool whole;

  @override
  Widget build(BuildContext context) => GestureDetector(
        key: Key('nearbyMedia-${media.id}'),
        onTap: onTap,
        child: media.uploading
            ? _UploadTile(media: media)
            : Stack(fit: StackFit.expand, children: [
                if (whole) ...[
                  const ColoredBox(color: Colors.black),
                  _picture(media.previewUrl, fit: BoxFit.contain),
                ] else
                  _picture(media.previewUrl),
                // a video that's ready plays here, muted, while on screen
                // (one under "+N" just opens full screen)
                if (media.isVideo && media.url != null && more == 0)
                  _FeedVideo(media: media)
                // a member's photo or video being compressed, or that couldn't be
                else if (media.processing || media.failed)
                  _StatusLabel(
                      media: media,
                      onRemove: media.failed &&
                              ServicesScope.nearbyUploadsOf(context) != null
                          ? () => _removeMedia(context, media.id)
                          : null)
                else if (media.isVideo) ...[
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
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

  /// Full screen (a video carries on there, with the same player).
  void _open(BuildContext context, List<NearbyMedia> media, int index) =>
      Navigator.of(context).push(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => NearbyMediaViewer(media: media, start: index)));

  @override
  Widget build(BuildContext context) {
    final uploads = ServicesScope.nearbyUploadsOf(context);
    // a member's one that isn't ready can be removed from here: then it
    // leaves at once
    if (uploads == null || media.every((m) => !m.uploading && !m.failed)) {
      return _grid(context, media);
    }
    return ListenableBuilder(
      listenable: uploads,
      builder: (context, _) => _grid(context, [
        for (final m in media)
          if (!uploads.removed(m.id)) m
      ]),
    );
  }

  Widget _grid(BuildContext context, List<NearbyMedia> media) {
    if (media.isEmpty) return const SizedBox.shrink();
    Widget tile(int i, {int more = 0, bool whole = false}) => _Tile(
        media: media[i],
        more: more,
        whole: whole,
        // a video still processing (or failed) has nothing to open yet
        onTap: media[i].url == null ? () {} : () => _open(context, media, i));
    const gap = SizedBox.square(dimension: 2);
    final Widget grid;
    if (media.length == 1) {
      // wide ones in their own shape (up to 2:1); tall ones (a phone's
      // video) in a square, so they don't take over the feed. Always whole
      // (never cropped): where the frame is wider than the picture (on a
      // computer, capped at nearbyMediaMaxHeight), black fills the sides
      final ratio = media.first.aspectRatio;
      grid = _Frame(
          aspectRatio: ratio < 1 ? 1 : ratio.clamp(1.0, 2.0),
          child: tile(0, whole: true));
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
/// videos play with sound (a tap pauses) - one playing in the feed carries
/// on from where it got to, with the same player (nothing loaded again).
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
            if (media.url == null) {
              // still processing (or failed): its still, and why
              return Stack(fit: StackFit.expand, children: [
                Center(child: _picture(media.previewUrl, fit: BoxFit.contain)),
                _StatusLabel(media: media),
              ]);
            }
            return media.isVideo
                // only the one on screen plays
                ? _Video(media: media, active: i == _index)
                : InteractiveViewer(
                    maxScale: 5,
                    child: Center(
                        child: _picture(media.url!,
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
  final _videos = _FeedVideos.instance;
  late final _SharedVideo _video = _videos.take(widget.media, fullScreen: true);
  bool _failed = false;

  VideoPlayerController get _player => _video.player;

  @override
  void initState() {
    super.initState();
    _player.addListener(_changed);
    _video.ready.then((_) {
      if (!mounted) return;
      setState(() {});
      _follow();
    }, onError: (Object _) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void didUpdateWidget(_Video old) {
    super.didUpdateWidget(old);
    _follow();
  }

  /// With sound while it's the one shown; waits otherwise.
  void _follow() {
    if (!_player.value.isInitialized) return;
    if (widget.active) {
      _player
        ..setVolume(1)
        ..play();
    } else {
      _player.pause();
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _player.removeListener(_changed);
    // back to the feed: it carries on there, muted or not as chosen
    _videos.give(_video, fullScreen: true);
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

/// One video's player, shared by the feed and full screen (so it carries
/// on, and nothing is loaded again), looping.
class _SharedVideo {
  _SharedVideo(this.mediaId, String url)
      : player = VideoPlayerController.networkUrl(Uri.parse(url)) {
    ready = player.initialize().then((_) => player.setLooping(true));
    ready.then((_) {}, onError: (Object _) {
      failed = true;
    });
  }

  bool failed = false;

  final int mediaId;
  final VideoPlayerController player;
  late final Future<void> ready;
  int holders = 0;
}

/// The feed's videos: the one most on screen (at least 60% of it) plays,
/// the rest wait - none while the app is in the background, and the feed
/// leaves alone one open full screen. Muted until unmuted, then for all of
/// them. Their players: shared with full screen, and the last few let go
/// kept ready (scrolling back doesn't load them again).
class _FeedVideos with WidgetsBindingObserver {
  _FeedVideos._() {
    WidgetsBinding.instance.addObserver(this);
  }

  static final instance = _FeedVideos._();

  /// How much of it has to be on screen to play.
  static const _enough = 0.6;

  /// Players no one holds, kept ready.
  static const _kept = 2;

  final muted = ValueNotifier<bool>(true);

  /// The one playing (a [_FeedVideoState]: the same video can be in the
  /// feed and on its post).
  final playing = ValueNotifier<Object?>(null);

  /// Open full screen (by media id): the feed leaves it alone.
  final fullScreen = <int>{};

  final _shown = <Object, double>{};
  bool _foreground = true;

  /// Most recently used last.
  final _players = <int, _SharedVideo>{};

  _SharedVideo take(NearbyMedia media, {bool fullScreen = false}) {
    final video =
        _players.remove(media.id) ?? _SharedVideo(media.id, media.url!);
    _players[media.id] = video;
    video.holders++;
    if (fullScreen) this.fullScreen.add(media.id);
    return video;
  }

  void give(_SharedVideo video, {bool fullScreen = false}) {
    video.holders--;
    if (fullScreen) {
      this.fullScreen.remove(video.mediaId);
      video.player.pause();
      // the feed takes it back (and plays it, if it's its turn)
      playing.value = null;
      _pick();
    }
    // the oldest ones no one holds go, beyond the few kept ready (one that
    // couldn't load goes at once)
    final idle = [
      for (final v in _players.values)
        if (v.holders <= 0) v
    ];
    final failed = [
      for (final v in idle)
        if (v.failed) v
    ];
    final ok = [
      for (final v in idle)
        if (!v.failed) v
    ];
    for (final v in [
      ...failed,
      if (ok.length > _kept) ...ok.take(ok.length - _kept),
    ]) {
      _players.remove(v.mediaId);
      v.player.dispose();
    }
  }

  void shown(Object tile, double fraction) {
    if (fraction > 0) {
      _shown[tile] = fraction;
    } else {
      _shown.remove(tile);
    }
    _pick();
  }

  void _pick() {
    Object? best;
    var most = _enough;
    // the one playing keeps playing, unless another is more on screen
    final current = playing.value;
    if (current != null && (_shown[current] ?? 0) >= _enough) {
      best = current;
      most = _shown[current]!;
    }
    for (final MapEntry(key: tile, value: fraction) in _shown.entries) {
      if (fraction > most || (best == null && fraction >= most)) {
        best = tile;
        most = fraction;
      }
    }
    playing.value = _foreground ? best : null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _pick();
  }
}

/// A video in the feed: plays where it is, muted, while it's the one most
/// on screen (and loops); waits when scrolled away or covered. Its length
/// (what's left, while playing) at the bottom left, mute or unmute at the
/// bottom right. Its still until its turn comes and it's loaded (only then:
/// a feed full of videos doesn't load them all), or when it can't play.
class _FeedVideo extends StatefulWidget {
  const _FeedVideo({required this.media});

  final NearbyMedia media;

  @override
  State<_FeedVideo> createState() => _FeedVideoState();
}

class _FeedVideoState extends State<_FeedVideo> {
  final _videos = _FeedVideos.instance;
  _SharedVideo? _video;
  bool _failed = false;

  VideoPlayerController? get _player => _video?.player;
  bool get _ready => _player?.value.isInitialized ?? false;

  @override
  void initState() {
    super.initState();
    _videos.playing.addListener(_follow);
    _videos.muted.addListener(_follow);
  }

  void _visible(VisibilityInfo info) {
    if (!mounted) return;
    final fraction = info.visibleFraction;
    // let go once none of it is on screen (kept ready a while)
    if (fraction == 0 && _video != null) setState(_letGo);
    _videos.shown(this, fraction);
  }

  void _load() {
    final video = _video = _videos.take(widget.media);
    video.player.addListener(_changed);
    video.ready.then((_) {
      if (_video == video) _follow();
    }, onError: (Object _) {
      if (_video != video || !mounted) return;
      setState(() {
        _letGo();
        _failed = true;
      });
    });
  }

  void _letGo() {
    final video = _video;
    _video = null;
    if (video == null) return;
    video.player.removeListener(_changed);
    _videos.give(video);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Its turn: loaded (once) and played at the chosen volume. Otherwise it
  /// waits. Not while it's open full screen (that plays it).
  void _follow() {
    if (!mounted) return;
    final mine = _videos.playing.value == this;
    if (mine && _video == null && !_failed) {
      setState(_load);
      return;
    }
    final player = _player;
    if (player == null ||
        !_ready ||
        _videos.fullScreen.contains(widget.media.id)) {
      return;
    }
    player.setVolume(_videos.muted.value ? 0 : 1);
    if (mine) {
      if (!player.value.isPlaying) player.play();
    } else if (player.value.isPlaying) {
      player.pause();
    }
  }

  @override
  void dispose() {
    _videos.playing.removeListener(_follow);
    _videos.muted.removeListener(_follow);
    _videos.shown(this, 0);
    _letGo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final ready = _ready;
    final playing = ready && player!.value.isPlaying;
    final duration = widget.media.duration;
    return VisibilityDetector(
      key: ObjectKey(this),
      onVisibilityChanged: _visible,
      child: Stack(fit: StackFit.expand, children: [
        if (ready)
          ColoredBox(
            color: Colors.black,
            child: Center(
              child: AspectRatio(
                  aspectRatio: player!.value.aspectRatio,
                  child: VideoPlayer(player)),
            ),
          ),
        if (!playing)
          const Center(
            child: DecoratedBox(
              decoration:
                  BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 30),
              ),
            ),
          ),
        if (duration != null)
          Positioned(
            left: 8,
            bottom: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                    mediaDurationLabel(
                        playing ? duration - player.value.position : duration),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        Positioned(
          right: 6,
          bottom: 6,
          child: ValueListenableBuilder<bool>(
            valueListenable: _videos.muted,
            builder: (context, muted, _) => IconButton(
              key: Key('nearbyMediaMute-${widget.media.id}'),
              tooltip: muted ? 'Unmute' : 'Mute',
              onPressed: () => _videos.muted.value = !muted,
              style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.6),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.square(36),
                  padding: EdgeInsets.zero),
              iconSize: 20,
              icon: Icon(
                  muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Over a member's photo or video that isn't ready: "Processing..." (it's
/// being compressed; it shows once ready), or that it couldn't be (with
/// Remove, for its author).
class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.media, this.onRemove});

  final NearbyMedia media;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _Pill(
            key: Key('nearbyMediaStatus-${media.id}'),
            busy: media.processing,
            text: media.processing
                ? 'Processing…'
                : "The ${media.isVideo ? 'video' : 'photo'} couldn't be "
                    'processed',
          ),
          if (onRemove != null)
            _RemoveButton(mediaId: media.id, onPressed: onRemove!),
        ]),
      );
}

/// A small dark label over a picture: a spinner (or a warning mark) and a
/// few words.
class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.busy, required this.text});

  final bool busy;
  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(999)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (busy)
              const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
            else
              const Icon(Icons.error_outline_rounded,
                  size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      );
}

/// Under a label on a dark picture: a light text button.
class _LabelButton extends StatelessWidget {
  const _LabelButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(foregroundColor: Colors.white),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.mediaId, required this.onPressed});

  final int mediaId;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => _LabelButton(
      key: Key('nearbyMediaRemove-$mediaId'),
      label: 'Remove',
      onPressed: onPressed);
}

/// Removes a member's photo or video that isn't ready from its post (the
/// post stays).
void _removeMedia(BuildContext context, int mediaId) {
  final uploads = ServicesScope.nearbyUploadsOf(context);
  final token = AppScope.read(context).sessionToken;
  if (uploads != null && token != null) uploads.remove(token, mediaId);
}

/// A member's photo or video still on its way from this device (only its
/// author gets one): how much is sent; that it failed (Try again, Remove);
/// or - the app was closed meanwhile, or it was sent from elsewhere - that
/// it didn't finish (Add again, Remove). Once stored: its still,
/// processing.
class _UploadTile extends StatelessWidget {
  const _UploadTile({required this.media});

  final NearbyMedia media;

  @override
  Widget build(BuildContext context) {
    final uploads = ServicesScope.nearbyUploadsOf(context);
    if (uploads == null) return _tile(context, null, null);
    return ListenableBuilder(
      listenable: uploads,
      builder: (context, _) => _tile(context, uploads, uploads.of(media.id)),
    );
  }

  Widget _tile(
      BuildContext context, NearbyUploads? uploads, NearbyUpload? upload) {
    if (upload?.stored case final stored?) {
      return Stack(fit: StackFit.expand, children: [
        _picture(stored.previewUrl),
        _StatusLabel(media: stored),
      ]);
    }
    final token = AppScope.read(context).sessionToken;
    final bytes = upload?.bytes;
    final Widget label;
    if (upload != null && upload.sending) {
      label = _Pill(
          key: Key('nearbyMediaUploading-${media.id}'),
          busy: true,
          text: 'Uploading ${(upload.sent * 100).floor()}%');
    } else {
      label = Column(mainAxisSize: MainAxisSize.min, children: [
        _Pill(
            key: Key('nearbyMediaStatus-${media.id}'),
            busy: false,
            text: upload?.error ?? "The upload didn't finish"),
        if (uploads != null && token != null)
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (bytes != null)
              _LabelButton(
                  key: Key('nearbyMediaRetry-${media.id}'),
                  label: 'Try again',
                  onPressed: () => uploads.retry(token, media.id))
            else
              _LabelButton(
                  key: Key('nearbyMediaAddAgain-${media.id}'),
                  label: 'Add again',
                  onPressed: () => _addAgain(context, uploads, token)),
            _RemoveButton(
                mediaId: media.id,
                onPressed: () => _removeMedia(context, media.id)),
          ]),
      ]);
    }
    return Stack(fit: StackFit.expand, children: [
      if (bytes != null && !(upload?.isVideo ?? media.isVideo))
        Image.memory(bytes, fit: BoxFit.cover)
      else
        _picture(null),
      Center(child: label),
    ]);
  }

  /// The file again, chosen from the library (a photo for a photo, a video
  /// for a video: the post was written for that).
  Future<void> _addAgain(
      BuildContext context, NearbyUploads uploads, String token) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final file = await ChatMediaPicker.instance.pickMedia();
    if (file == null) return;
    if (await file.length() > NearbyService.maxUploadBytes) {
      messenger?.showSnackBar(const SnackBar(
          content: Text('The file is too large. The maximum is 100 MB.')));
      return;
    }
    uploads.addAgain(token, media.id,
        bytes: await file.readAsBytes(),
        filename: file.name.isNotEmpty
            ? file.name
            : (media.isVideo ? 'video.mp4' : 'photo.jpg'),
        isVideo: media.isVideo);
  }
}
