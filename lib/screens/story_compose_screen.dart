import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:video_player/video_player.dart';

import '../services/huntr_backend.dart';
import '../services/services_scope.dart';
import '../services/story_service.dart';
import '../services/story_upload.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/photos/photo_crop_screen.dart';
import '../widgets/chat/picked_video_io.dart'
    if (dart.library.js_interop) '../widgets/chat/picked_video_web.dart';
import '../widgets/profile/gradient_button.dart';
import '../widgets/stories/trim_window.dart';
import '../widgets/stories/video_filmstrip.dart';
import 'story_camera_screen.dart';

/// Adds a story: records it now with the camera ([StoryCameraScreen]; from
/// the gallery only for verified people, who get longer stories and photos
/// too: [StoryService.limitsFor]), then [StoryComposeScreen]. True once
/// one is posting ([storyUpload]: it goes up in the background).
Future<bool> addToStory(BuildContext context, StoryService service) async {
  if (storyUpload.active) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Your story is still posting. Add another once '
            "it's up.")));
    return false;
  }
  if (!await _roomForAnother(context, service)) return false;
  if (!context.mounted) return false;
  final limits = StoryService.limitsFor(verified: await _verifiedNow(context));
  while (true) {
    if (!context.mounted) return false;
    final video = await Navigator.of(context).push<XFile>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryCameraScreen(
            maxLength: limits.maxLength, album: limits.fromAlbum)));
    if (video == null || !context.mounted) return false;
    final posted = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => StoryComposeScreen(
            service: service, video: video, limits: limits)));
    // "Retake" (false): record again; back or posting: done
    if (posted != false) return posted == true;
  }
}

/// Says how a story posted in the background went: up, or what went wrong
/// with Try again.
void announceStoryUpload(ScaffoldMessengerState messenger, bool posted) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(posted
        ? const SnackBar(
            content: Text('Your story is up for the next 24 hours ✨'))
        : SnackBar(
            duration: const Duration(seconds: 8),
            content: Text(storyUpload.error ?? "Your story wasn't posted."),
            action: SnackBarAction(
                label: 'Try again',
                onPressed: () => storyUpload
                    .retry()
                    .then((posted) => announceStoryUpload(messenger, posted))),
          ));
}

/// Whether I have the blue check now, from my profile: an admin may have
/// verified me since the app opened. When it can't be checked, what the
/// app knew is used (the backend still decides what's allowed).
Future<bool> _verifiedNow(BuildContext context) async {
  final app = AppScope.read(context);
  final profiles = ServicesScope.profilesOf(context);
  final token = app.sessionToken;
  if (profiles == null || token == null) return app.myVerified;
  try {
    app.myVerified = (await profiles.fetchMine(token)).verified;
  } catch (error) {
    debugPrint('Blue check not checked: $error');
  }
  return app.myVerified;
}

/// Whether I can add a story ([StoryService.maxActive] at most): says so
/// before the camera opens, rather than after recording. When my stories
/// can't be checked, the camera opens (the backend still decides).
Future<bool> _roomForAnother(BuildContext context, StoryService service) async {
  final app = AppScope.read(context);
  final token = app.sessionToken;
  if (token == null) return false;
  try {
    final mine = await service.mine(token);
    if (mine.length < StoryService.maxActive) return true;
  } on SessionRejectedException {
    app.endSession();
    return false;
  } catch (error) {
    debugPrint('My stories not checked: $error');
    return true;
  }
  if (!context.mounted) return false;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('storyLimit'),
      icon: Icon(Icons.auto_awesome_rounded, color: HuntrColors.orange),
      title: Text("You've got ${StoryService.maxActive} stories up"),
      content: const Text(
          "That's the most at once. Each one disappears 24 hours after you "
          'post it, or you can delete one from Your stories to add another.'),
      actions: [
        FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it')),
      ],
    ),
  );
  return false;
}

/// A story just recorded (or chosen), before it's posted: full screen, as
/// people will watch it (the photo, or the video playing: tap to pause),
/// with the part to keep for a longer video, that it's public for 24 hours,
/// and Share, which posts it in the background and pops true ([storyUpload];
/// false: record again).
class StoryComposeScreen extends StatefulWidget {
  const StoryComposeScreen(
      {super.key,
      required this.service,
      required this.video,
      this.limits = const StoryLimits(
          maxLength: StoryService.maxLength,
          maxSourceLength: StoryService.maxSourceLength,
          maxUploadBytes: StoryService.maxUploadBytes,
          fromAlbum: false)});

  final StoryService service;

  /// The recording, or the file chosen (a photo from a verified person's
  /// album).
  final XFile video;
  final StoryLimits limits;

  @override
  State<StoryComposeScreen> createState() => _StoryComposeScreenState();
}

/// A photo, by its name (the album's photos come as JPEG).
bool _isPhoto(XFile file) {
  final type = file.mimeType;
  if (type != null) return type.startsWith('image/');
  final name = (file.name.isEmpty ? file.path : file.name).toLowerCase();
  return const ['.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif']
      .any(name.endsWith);
}

class _StoryComposeScreenState extends State<StoryComposeScreen> {
  late final bool _photo = _isPhoto(widget.video);

  /// The photo's bytes and size, once read (a photo story).
  Uint8List? _photoBytes;
  Size? _photoSize;

  /// Fill: the story filled, pinch and drag to choose the part that shows;
  /// or Fit: the whole picture, on black. Null until the user picks: an
  /// upright picture starts filled, a wide one fitted.
  bool? _fill;
  final _framing = TransformationController();

  /// The 9:16 frame on screen (what's inside it is what's posted).
  Size? _frameSize;

  /// The user has moved or zoomed it (the hint goes).
  bool _framed = false;

  /// The picture's size (null until known).
  Size? get _mediaSize {
    final size = _photo ? _photoSize : _player?.value.size;
    return size == null || size.isEmpty ? null : size;
  }

  bool get _filling {
    final media = _mediaSize;
    return _fill ?? (media == null || media.width / media.height <= 0.8);
  }

  late final VideoPlayerController? _player =
      _photo ? null : pickedVideoController(widget.video.path);
  bool _ready = false;

  Duration get _maxLength => widget.limits.maxLength;

  /// A longer file (the website on a computer, a verified person's album):
  /// the [_maxLength] kept starts here; the user slides it.
  Duration _start = Duration.zero;

  bool get _trimming =>
      _ready &&
      !_photo &&
      _length > _maxLength + const Duration(milliseconds: 500);

  /// Reading the file to post it (then it goes up in the background).
  bool _reading = false;
  String? _error;

  /// How long the video is; zero when the browser can't tell (an iPhone's
  /// Safari may call a chosen video endless).
  Duration get _length {
    final duration = _player?.value.duration ?? Duration.zero;
    return duration.isNegative ? Duration.zero : duration;
  }

  @override
  void initState() {
    super.initState();
    final player = _player;
    if (player == null) {
      widget.video.readAsBytes().then((bytes) async {
        final image = await decodeImageFromList(bytes);
        final size = Size(image.width.toDouble(), image.height.toDouble());
        image.dispose();
        if (mounted) {
          setState(() {
            _photoBytes = bytes;
            _photoSize = size;
            _ready = true;
          });
        }
      }).catchError((Object error) {
        if (mounted) {
          setState(
              () => _error = "This photo can't be opened. Choose another.");
        }
      });
      return;
    }
    player.initialize().then((_) {
      if (!mounted) return;
      // a file may be longer than a recording: then the user picks which
      // part to keep (from a video up to a few minutes long)
      final long = _length > _maxLength + const Duration(milliseconds: 500);
      final source = widget.limits.maxSourceLength;
      if (long && _length > source) {
        setState(() => _error = 'This video is too long to trim. Choose one '
            'up to ${storyLengthWords(source)}, or record one.');
        return;
      }
      player
        ..setLooping(true)
        ..addListener(_keepInWindow)
        ..play();
      setState(() => _ready = true);
    }).catchError((Object error) {
      if (mounted) {
        setState(() =>
            _error = "This recording can't be played. Please record again.");
      }
    });
  }

  @override
  void dispose() {
    _player?.dispose();
    _framing.dispose();
    super.dispose();
  }

  /// The picture scaled to just cover [frame] (Fill, before any zoom).
  static Size _cover(Size media, Size frame) {
    final scale =
        math.max(frame.width / media.width, frame.height / media.height);
    return Size(media.width * scale, media.height * scale);
  }

  /// Fill, unzoomed, its middle in the frame's middle.
  void _centerFill(Size frame) {
    final media = _mediaSize;
    if (media == null) return;
    final cover = _cover(media, frame);
    _framing.value = Matrix4.identity()
      ..translateByDouble((frame.width - cover.width) / 2,
          (frame.height - cover.height) / 2, 0, 1);
  }

  /// The picture in the frame: Fill (covering it; pinch and drag to choose
  /// the part) or Fit (all of it, on black). The picture never takes
  /// touches itself (in a browser a video is a page element that would
  /// swallow them): a PointerInterceptor over it gives them to HUNTR.
  Widget _picture(Size frame) {
    final media = _mediaSize;
    final player = _player;
    final photo = _photoBytes;
    if (!_ready || media == null || (photo == null && player == null)) {
      return Center(
          child: CircularProgressIndicator(color: HuntrColors.orange));
    }
    final shown = IgnorePointer(
      child: photo != null
          ? Image.memory(photo,
              key: const Key('storyPhotoPreview'),
              fit: BoxFit.fill,
              gaplessPlayback: true)
          : VideoPlayer(player!),
    );
    final touches = Positioned.fill(
        child: PointerInterceptor(child: const SizedBox.expand()));
    if (!_filling) {
      final scale =
          math.min(frame.width / media.width, frame.height / media.height);
      return Stack(children: [
        Center(
          child: SizedBox(
              width: media.width * scale,
              height: media.height * scale,
              child: shown),
        ),
        touches,
      ]);
    }
    final cover = _cover(media, frame);
    return InteractiveViewer(
      key: const Key('storyFrame'),
      transformationController: _framing,
      constrained: false,
      minScale: 1,
      maxScale: 5,
      clipBehavior: Clip.hardEdge,
      onInteractionStart: (_) {
        if (!_framed) setState(() => _framed = true);
      },
      child: SizedBox(
        width: cover.width,
        height: cover.height,
        child: Stack(children: [Positioned.fill(child: shown), touches]),
      ),
    );
  }

  void _toggleFill() {
    final frame = _frameSize;
    setState(() {
      _fill = !_filling;
      _framed = false;
    });
    if (frame != null) _centerFill(frame);
  }

  /// While trimming, the preview loops over the part kept only.
  void _keepInWindow() {
    final player = _player;
    if (!_trimming || player == null) return;
    final at = player.value.position;
    if (at < _start || at >= _start + _maxLength) {
      player.seekTo(_start);
    }
  }

  Future<void> _post() async {
    final app = AppScope.read(context);
    final token = app.sessionToken;
    if (token == null || _reading) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _reading = true;
      _error = null;
    });
    final List<int> bytes;
    try {
      bytes = _photoBytes ?? await widget.video.readAsBytes();
    } catch (error) {
      if (mounted) {
        setState(() {
          _reading = false;
          _error = "This ${_photo ? 'photo' : 'video'} can't be read. "
              'Choose another.';
        });
      }
      return;
    }
    final limit = widget.limits.maxUploadBytes;
    if (bytes.length > limit) {
      if (mounted) {
        setState(() {
          _reading = false;
          _error = 'This ${_photo ? 'photo' : 'video'} is too large. The '
              'maximum is ${limit ~/ (1024 * 1024)} MB.';
        });
      }
      return;
    }
    _player?.pause();
    final service = widget.service;
    final filename = widget.video.name.isEmpty ? 'story' : widget.video.name;
    final start = _trimming ? _start : Duration.zero;
    // a recording: all of it (the camera stops at the limit); a longer
    // file: the part picked (the backend cuts it); a photo: the backend
    // shows it for StoryService.photoLength; a length the browser can't
    // tell: none, the backend keeps up to my limit
    final length = _photo
        ? StoryService.photoLength
        : _length == Duration.zero
            ? null
            : _length < _maxLength
                ? _length
                : _maxLength;
    // as framed: the part that fills the story, or the whole of it
    final media = _mediaSize;
    final frame = _frameSize;
    final fill = _filling;
    final crop = fill && media != null && frame != null
        ? cropForViewport(
            displaySize: _cover(media, frame),
            viewport: frame.width,
            viewportHeight: frame.height,
            transform: _framing.value)
        : null;
    unawaited(storyUpload.start((onProgress) async {
      try {
        await service.post(token,
            bytes: bytes,
            filename: filename,
            start: start,
            length: length,
            crop: crop,
            fit: !fill && media != null,
            onProgress: onProgress);
      } on SessionRejectedException {
        app.endSession();
        rethrow;
      }
    }).then((posted) => announceStoryUpload(messenger, posted)));
    navigator.pop(true);
  }

  void _togglePlay() {
    final player = _player;
    if (player == null || !_ready) return;
    setState(() => player.value.isPlaying ? player.pause() : player.play());
  }

  /// What "Public · 24 hours" means.
  void _explainPublic() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.public_rounded, color: HuntrColors.orange),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                    'Stories are public. People nearby can watch it for 24 '
                    'hours. You can see who watched, and delete it any time.'),
              ),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final paused = _ready && player != null && !player.value.isPlaying;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(children: [
              // ---- the story: a 9:16 frame, what's in it is posted ----
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 9 / 16,
                      // a faint edge: the story's shape shows even when Fit
                      // leaves black above and below
                      child: Container(
                        foregroundDecoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: LayoutBuilder(builder: (context, box) {
                            final frame = box.biggest;
                            if (_frameSize != frame) {
                              _frameSize = frame;
                              // Fill starts centered in the new frame
                              WidgetsBinding.instance.addPostFrameCallback(
                                  (_) => mounted ? _centerFill(frame) : null);
                            }
                            return Stack(children: [
                              Positioned.fill(
                                child: ColoredBox(
                                  color: Colors.black,
                                  // tap: pause or play
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _togglePlay,
                                    child: _picture(frame),
                                  ),
                                ),
                              ),
                              if (paused)
                                const Center(
                                  child: IgnorePointer(
                                    child: CircleAvatar(
                                      radius: 34,
                                      backgroundColor: Colors.black54,
                                      child: Icon(Icons.play_arrow_rounded,
                                          color: Colors.white, size: 44),
                                    ),
                                  ),
                                ),
                              // what Fill lets you do, until it's done
                              if (_ready && _filling && !_framed)
                                const Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 14,
                                  child: IgnorePointer(
                                    child: Center(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius: BorderRadius.all(
                                                Radius.circular(20))),
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 6),
                                          child: Text(
                                              'Pinch and drag to choose what shows',
                                              key: Key('storyFrameHint'),
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12.5)),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              // ---- top: discard, retake ----
                              Positioned(
                                left: 0,
                                right: 0,
                                top: 0,
                                child: DecoratedBox(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black54,
                                          Colors.transparent
                                        ]),
                                  ),
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(4, 4, 4, 28),
                                    child: Row(children: [
                                      _OverlayIcon(
                                        key: const Key('storyComposeClose'),
                                        tooltip: 'Discard',
                                        icon: Icons.close_rounded,
                                        onPressed: _reading
                                            ? null
                                            : () => Navigator.of(context).pop(),
                                      ),
                                      const Spacer(),
                                      if (_ready && _mediaSize != null)
                                        _OverlayIcon(
                                          key: const Key('storyFrameToggle'),
                                          tooltip: _filling
                                              ? 'Show all of it'
                                              : 'Fill the story',
                                          icon: _filling
                                              ? Icons.fit_screen_rounded
                                              : Icons.crop_free_rounded,
                                          onPressed:
                                              _reading ? null : _toggleFill,
                                        ),
                                      _OverlayIcon(
                                        key: const Key('storyRetake'),
                                        tooltip:
                                            _photo ? 'Choose again' : 'Retake',
                                        icon: Icons.replay_rounded,
                                        onPressed: _reading
                                            ? null
                                            : () => Navigator.of(context)
                                                .pop(false),
                                      ),
                                    ]),
                                  ),
                                ),
                              ),
                            ]);
                          }),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ---- below: the part to keep, who sees it, Share ----
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_trimming && player != null) ...[
                      Row(children: [
                        Icon(Icons.content_cut_rounded,
                            size: 18, color: HuntrColors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Pick ${storyLengthWords(_maxLength)}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ),
                        Text(
                            '${_clock(_start)} → '
                            '${_clock(_start + _maxLength)}',
                            key: const Key('storyTrimRange'),
                            style: TextStyle(
                                color: HuntrColors.orange,
                                fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 10),
                      ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: player,
                        builder: (_, value, __) => TrimWindow(
                          total: _length,
                          window: _maxLength,
                          start: _start,
                          position: value.position,
                          // frames from across the video, so the part
                          // picked shows what's in it
                          background: VideoFilmstrip(
                              path: widget.video.path, length: _length),
                          // the preview follows while it's moved
                          onChanged: _reading
                              ? (_) {}
                              : (start) {
                                  setState(() => _start = start);
                                  player.seekTo(start);
                                },
                          onChangeEnd: () => player.seekTo(_start),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_error case final error?) ...[
                      Text(error,
                          key: const Key('storyComposeError'),
                          style: const TextStyle(color: HuntrColors.coral)),
                      const SizedBox(height: 12),
                    ],
                    // who sees it (tap: what that means)
                    Center(
                      child: InkWell(
                        key: const Key('storyPublicNotice'),
                        borderRadius: BorderRadius.circular(20),
                        onTap: _explainPublic,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.public_rounded,
                                size: 16, color: HuntrColors.orange),
                            const SizedBox(width: 6),
                            const Text('Public · 24 hours',
                                style: TextStyle(color: HuntrColors.muted)),
                            const SizedBox(width: 4),
                            const Icon(Icons.info_outline_rounded,
                                size: 15, color: HuntrColors.muted),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    GradientButton(
                      key: const Key('postStory'),
                      icon: Icons.send_rounded,
                      label: _reading ? 'Sharing…' : 'Share to story',
                      onPressed: _ready && !_reading ? _post : null,
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A plain white icon over the story (a soft shadow keeps it visible on
/// light pictures): no disc, no outline.
class _OverlayIcon extends StatelessWidget {
  const _OverlayIcon(
      {super.key,
      required this.icon,
      required this.tooltip,
      required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: 30,
        color: Colors.white,
        icon: Icon(icon,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 10)]),
      );
}

/// "0:07", "1:23".
String _clock(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
