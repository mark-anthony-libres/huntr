import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../services/huntr_backend.dart';
import '../services/story_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/chat/picked_video_io.dart'
    if (dart.library.js_interop) '../widgets/chat/picked_video_web.dart';
import '../widgets/profile/gradient_button.dart';
import 'story_camera_screen.dart';

/// Adds a story: records it now with the camera ([StoryCameraScreen]; never
/// from the gallery), then [StoryComposeScreen]. True once one was posted.
Future<bool> addToStory(BuildContext context, StoryService service) async {
  if (!await _roomForAnother(context, service)) return false;
  while (true) {
    if (!context.mounted) return false;
    final video = await Navigator.of(context).push<XFile>(MaterialPageRoute(
        fullscreenDialog: true, builder: (_) => const StoryCameraScreen()));
    if (video == null || !context.mounted) return false;
    final posted = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => StoryComposeScreen(service: service, video: video)));
    // "Retake" (false): record again; back or posted: done
    if (posted != false) return posted == true;
  }
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
      icon: const Icon(Icons.auto_awesome_rounded, color: HuntrColors.orange),
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

/// A story just recorded, before it's posted: plays it, says that stories
/// are public, and shares it (or pops false to record again).
class StoryComposeScreen extends StatefulWidget {
  const StoryComposeScreen(
      {super.key, required this.service, required this.video});

  final StoryService service;
  final XFile video;

  @override
  State<StoryComposeScreen> createState() => _StoryComposeScreenState();
}

class _StoryComposeScreenState extends State<StoryComposeScreen> {
  late final VideoPlayerController _player =
      pickedVideoController(widget.video.path);
  bool _ready = false;
  double? _sent; // upload progress while posting
  String? _error;

  Duration get _length => _player.value.duration;

  @override
  void initState() {
    super.initState();
    _player.initialize().then((_) {
      if (!mounted) return;
      // a file (the website on a computer) may be longer than a recording
      if (_length >
          StoryService.maxLength + const Duration(milliseconds: 500)) {
        setState(() => _error =
            'This video is ${(_length.inMilliseconds / 1000).toStringAsFixed(1)} '
                'seconds long. Stories are up to '
                '${StoryService.maxLength.inSeconds} seconds: choose a shorter '
                'one, or record one.');
        return;
      }
      _player
        ..setLooping(true)
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
    _player.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final app = AppScope.read(context);
    final token = app.sessionToken;
    if (token == null || _sent != null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _sent = 0;
      _error = null;
    });
    try {
      final bytes = await widget.video.readAsBytes();
      if (bytes.length > StoryService.maxUploadBytes) {
        throw const BackendException(
            'This video is too large. The maximum is 50 MB.');
      }
      _player.pause();
      // all of it (the camera stops at StoryService.maxLength)
      await widget.service.post(token,
          bytes: bytes,
          filename: widget.video.name.isEmpty ? 'story' : widget.video.name,
          start: Duration.zero,
          length: _length < StoryService.maxLength
              ? _length
              : StoryService.maxLength, onProgress: (sent) {
        if (mounted) setState(() => _sent = sent);
      });
      messenger.showSnackBar(const SnackBar(
          content: Text('Your story is up for the next 24 hours ✨')));
      navigator.pop(true);
    } on SessionRejectedException {
      app.endSession();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sent = null;
        _error = error is BackendException
            ? error.message
            : "Your story wasn't posted. Check your connection and try again.";
      });
      _player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sending = _sent != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('New story'),
        actions: [
          TextButton.icon(
            key: const Key('storyRetake'),
            onPressed:
                _sent == null ? () => Navigator.of(context).pop(false) : null,
            icon: const Icon(Icons.replay_rounded),
            label: const Text('Retake'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          // everything on one screen: the preview takes the room left
          // over, so Share is always in view (no scrolling)
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---- the preview ----
                  Expanded(
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: ColoredBox(
                          color: Colors.black,
                          child: AspectRatio(
                            aspectRatio:
                                _ready ? _player.value.aspectRatio : 9 / 16,
                            child: _ready
                                ? GestureDetector(
                                    onTap: () => setState(() =>
                                        _player.value.isPlaying
                                            ? _player.pause()
                                            : _player.play()),
                                    child: VideoPlayer(_player))
                                : const Center(
                                    child: CircularProgressIndicator(
                                        color: HuntrColors.orange)),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ---- public notice ----
                  const SizedBox(height: 16),
                  Container(
                    key: const Key('storyPublicNotice'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: HuntrColors.orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: HuntrColors.orange.withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.public_rounded, color: HuntrColors.orange),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Stories are public. People nearby can watch it '
                              'for 24 hours. You can see who watched, and delete '
                              'it any time.',
                            ),
                          ),
                        ]),
                  ),

                  if (_error case final error?) ...[
                    const SizedBox(height: 12),
                    Text(error,
                        style: const TextStyle(color: HuntrColors.coral)),
                  ],
                  const SizedBox(height: 16),
                  if (sending) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                          value: _sent! < 1 ? _sent : null,
                          color: HuntrColors.orange),
                    ),
                    const SizedBox(height: 8),
                    Text(
                        _sent! < 1
                            ? 'Uploading ${(_sent! * 100).round()}%'
                            : 'Getting it ready…',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: HuntrColors.muted)),
                    const SizedBox(height: 12),
                  ],
                  GradientButton(
                    key: const Key('postStory'),
                    icon: Icons.auto_awesome_rounded,
                    label: sending ? 'Posting…' : 'Share to your story',
                    onPressed: _ready && !sending ? _post : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
