import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../flows/chat_attachments.dart';
import '../flows/media_permission.dart' show openAppSettingsAndWait;
import '../services/story_service.dart';
import '../theme.dart';
import '../widgets/stories/story_round_button.dart';

/// Records a story right now, with the camera: up to
/// [StoryService.maxLength], and it stops by itself then. There's no way to
/// pick a video from the gallery: a story is a moment as it happens. Pops
/// with the recording, or null.
///
/// With [story] false it's the chat's camera on a computer's browser (whose
/// file input can't open the webcam): a [photo], or a video up to
/// [maxLength]; without a camera, a file can be chosen instead.
class StoryCameraScreen extends StatefulWidget {
  const StoryCameraScreen(
      {super.key, this.story = true, this.photo = false, this.maxLength});

  /// A story (the default); false: a photo or video for a chat.
  final bool story;

  /// Takes a photo instead of recording.
  final bool photo;

  /// The longest recording (stories: [StoryService.maxLength]).
  final Duration? maxLength;

  /// The shortest recording a story takes.
  static const minLength = Duration(seconds: 1);

  /// The website on a computer (often without a camera) may also take a
  /// video file (still at most [StoryService.maxLength]); the apps and phone
  /// browsers only record.
  /// A phone's browser (Chrome, Brave, Safari on a phone): if the browser
  /// can't open the camera itself, the phone's camera app records instead.
  static bool get phoneBrowser =>
      kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get canChooseFile =>
      kIsWeb &&
      defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS;

  @override
  State<StoryCameraScreen> createState() => _StoryCameraScreenState();
}

class _StoryCameraScreenState extends State<StoryCameraScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  List<CameraDescription> _cameras = const [];
  int _which = 0;
  CameraController? _camera;

  /// What's wrong (no camera, not allowed), said kindly.
  ({String title, String body, String? blocked})? _problem;
  bool _starting = true;

  /// Runs while recording: the ring around the button, and the stop at
  /// [StoryService.maxLength].
  late final AnimationController _recording;
  bool _stopping = false;

  bool get _isRecording => _camera?.value.isRecordingVideo ?? false;

  Duration get _maxLength => widget.maxLength ?? StoryService.maxLength;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recording = AnimationController(vsync: this, duration: _maxLength)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _stop();
      });
    _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recording.dispose();
    _camera?.dispose();
    super.dispose();
  }

  /// The camera was let go because HUNTR went to the background.
  bool _releasedInBackground = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // the apps let a working camera go while HUNTR is in the background (a
    // recording cut short is dropped), and open it again on return. Never
    // because of a permission prompt (it makes the app inactive for a
    // moment): that reopened it, asked again, and looped. Not in a browser
    // at all: it looks after the camera itself.
    if (kIsWeb || _opening) return;
    if (state == AppLifecycleState.inactive) {
      final camera = _camera;
      if (camera == null) return;
      _recording.reset();
      setState(() => _camera = null);
      camera.dispose();
      _releasedInBackground = true;
    } else if (state == AppLifecycleState.resumed && _releasedInBackground) {
      _releasedInBackground = false;
      _open();
    }
  }

  /// Opening the camera now (never twice at once).
  bool _opening = false;

  /// Retries made by themselves after a failed start (phones' browsers
  /// often can't open a camera the moment another one was let go).
  int _autoRetries = 0;

  /// What the camera said when it failed (shown small, for support).
  String? _problemCode;

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    var retry = false;
    setState(() {
      _starting = true;
      _problem = null;
    });
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
        // the back camera first, when there is one
        final back = _cameras
            .indexWhere((c) => c.lensDirection == CameraLensDirection.back);
        _which = back < 0 ? 0 : back;
      }
      if (_cameras.isEmpty) {
        throw CameraException('NoCamera', 'No camera found.');
      }
      final camera = CameraController(_cameras[_which], ResolutionPreset.high,
          enableAudio: !widget.photo);
      await camera.initialize();
      if (!widget.photo) await camera.prepareForVideoRecording();
      if (!mounted) {
        await camera.dispose();
        return;
      }
      setState(() {
        _camera = camera;
        _starting = false;
      });
    } on CameraException catch (error) {
      debugPrint('Story camera failed: ${error.code} ${error.description}');
      if (!mounted) return;
      final problem = _explain(error);
      final code = error.code.toLowerCase();
      if (problem.blocked == null &&
          !code.contains('notfound') &&
          !code.contains('nocamera') &&
          _autoRetries < 2) {
        // try again by itself, from the camera list, after a moment
        _autoRetries++;
        _cameras = const [];
        retry = true;
      } else {
        setState(() {
          _starting = false;
          _problem = problem;
          _problemCode = error.code;
        });
      }
    } catch (error) {
      // anything else (e.g. no camera support here): say so, never spin
      debugPrint('Story camera failed: $error');
      if (!mounted) return;
      setState(() {
        _starting = false;
        _problem = _explain(CameraException('Unavailable', '$error'));
        _problemCode = '${error.runtimeType}';
      });
    } finally {
      _opening = false;
    }
    if (retry) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (mounted) await _open();
    }
  }

  /// A phone's browser: record with the phone's own camera app (it opens
  /// straight to recording - still nothing from the gallery).
  Future<void> _recordWithPhone() async {
    try {
      final picker = ChatMediaPicker.instance;
      final video = widget.photo
          ? await picker.takePhoto()
          : await picker.recordVideo(maxDuration: _maxLength);
      if (video != null && mounted) Navigator.of(context).pop(video);
    } catch (error) {
      debugPrint('Phone camera not opened: $error');
    }
  }

  /// The problem, kindly; [blocked] names a permission that's off
  /// ('Camera' or 'Microphone'), which gets steps to turn it on.
  ({String title, String body, String? blocked}) _explain(
      CameraException error) {
    final code = error.code.toLowerCase();
    final seconds = _maxLength.inSeconds;
    final what = widget.story
        ? 'record a story'
        : widget.photo
            ? 'take a photo'
            : 'record a video';
    final refused = code.contains('denied') ||
        code.contains('restricted') ||
        code.contains('permission');
    if (refused && code.contains('audio')) {
      return (
        title: "Let's turn your microphone on",
        body: widget.story
            ? 'Stories have sound, so HUNTR needs your microphone too.'
            : 'Videos have sound, so HUNTR needs your microphone too.',
        blocked: 'Microphone',
      );
    }
    if (refused) {
      return (
        title: "Let's turn your camera on",
        body: widget.photo
            ? 'HUNTR needs your camera to $what.'
            : 'HUNTR needs your camera and microphone to $what.',
        blocked: 'Camera',
      );
    }
    if (code.contains('nocamera') || code.contains('notfound')) {
      return StoryCameraScreen.canChooseFile
          ? (
              title: 'No camera here',
              body: !widget.story
                  ? 'No problem, you can choose a file instead.'
                  : 'No problem, you can upload a short clip instead '
                      '(up to $seconds seconds).',
              blocked: null,
            )
          : (
              title: 'No camera found',
              body: 'HUNTR needs a camera to $what. Try on a phone with '
                  'one.',
              blocked: null,
            );
    }
    return (
      title: "The camera didn't start",
      body: StoryCameraScreen.phoneBrowser
          ? "Your browser couldn't open the camera here. Record with your "
              "phone's camera instead, or tap Try again."
          : 'It might be open in another app. Close it, then tap Try again.',
      blocked: null,
    );
  }

  /// Phones: HUNTR's settings, then the camera again on coming back.
  Future<void> _openSettings() async {
    await openAppSettingsAndWait();
    if (!mounted) return;
    _cameras = const [];
    await _open();
  }

  void _tryAgain() {
    _cameras = const [];
    _autoRetries = 0;
    _problemCode = null;
    _open();
  }

  Future<void> _switch() async {
    if (_cameras.length < 2 || _isRecording) return;
    final old = _camera;
    setState(() {
      _which = (_which + 1) % _cameras.length;
      _camera = null;
    });
    await old?.dispose();
    await _open();
  }

  Future<void> _start() async {
    final camera = _camera;
    if (camera == null || _isRecording) return;
    try {
      await camera.startVideoRecording();
      _recording.forward(from: 0);
      setState(() {});
    } on CameraException catch (error) {
      setState(() => _problem = _explain(error));
    }
  }

  Future<void> _stop() async {
    final camera = _camera;
    if (camera == null || !_isRecording || _stopping) return;
    _stopping = true;
    _recording.stop();
    try {
      final video = await camera.stopVideoRecording();
      if (mounted) Navigator.of(context).pop(video);
    } on CameraException catch (error) {
      if (mounted) setState(() => _problem = _explain(error));
    } finally {
      _stopping = false;
      _recording.reset();
    }
  }

  /// Taking a photo now (photo mode).
  bool _snapping = false;

  Future<void> _snap() async {
    final camera = _camera;
    if (camera == null || _snapping) return;
    _snapping = true;
    try {
      final photo = await camera.takePicture();
      if (mounted) Navigator.of(context).pop(photo);
    } on CameraException catch (error) {
      if (mounted) setState(() => _problem = _explain(error));
    } finally {
      _snapping = false;
    }
  }

  /// A file instead (the website on a computer only).
  Future<void> _chooseFile() async {
    if (_isRecording) return;
    final picker = ChatMediaPicker.instance;
    final file =
        widget.photo ? await picker.pickImage() : await picker.pickVideo();
    if (file != null && mounted) Navigator.of(context).pop(file);
  }

  /// Long enough to stop (a story is at least [StoryCameraScreen.minLength]).
  bool get _canStop =>
      _recording.value * _maxLength.inMilliseconds >=
      StoryCameraScreen.minLength.inMilliseconds;

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          // ---- what the camera sees ----
          Positioned.fill(
            child: Center(
              child: camera != null && camera.value.isInitialized
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: CameraPreview(camera))
                  : _problem == null
                      ? CircularProgressIndicator(color: HuntrColors.orange)
                      : const SizedBox.shrink(),
            ),
          ),

          // ---- top: close, why live only, switch camera ----
          Positioned(
            left: 12,
            right: 12,
            top: 10,
            child: Column(children: [
              Row(children: [
                StoryRoundButton(
                  key: const Key('storyCameraClose'),
                  tooltip: 'Close',
                  icon: Icons.close_rounded,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                if (_cameras.length > 1)
                  StoryRoundButton(
                    key: const Key('storyCameraSwitch'),
                    tooltip: 'Switch camera',
                    icon: Icons.cameraswitch_rounded,
                    onPressed: _isRecording ? null : _switch,
                  ),
              ]),
              // what stories are for (not over a problem: that says enough)
              if (_problem == null && widget.story) ...[
                const SizedBox(height: 12),
                _LiveOnlyLabel(fileToo: StoryCameraScreen.canChooseFile),
              ],
            ]),
          ),

          // ---- a problem (no camera, not allowed: how to allow it) ----
          if (_problem case final problem?)
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        problem.blocked == 'Microphone'
                            ? Icons.mic_off_rounded
                            : Icons.videocam_off_rounded,
                        color: HuntrColors.orange,
                        size: 44),
                    const SizedBox(height: 14),
                    Text(problem.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(problem.body,
                        key: const Key('storyCameraProblem'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white70, height: 1.4)),
                    if (_problemCode case final code?) ...[
                      const SizedBox(height: 6),
                      Text('($code)',
                          key: const Key('storyCameraCode'),
                          style: const TextStyle(
                              color: HuntrColors.muted, fontSize: 11)),
                    ],
                    if (problem.blocked != null) ...[
                      const SizedBox(height: 18),
                      const _AllowSteps(),
                    ],
                    const SizedBox(height: 18),
                    // a phone's browser: its camera app always works
                    if (StoryCameraScreen.phoneBrowser) ...[
                      FilledButton.icon(
                        key: const Key('storyPhoneCamera'),
                        onPressed: _recordWithPhone,
                        icon: Icon(widget.photo
                            ? Icons.photo_camera_rounded
                            : Icons.videocam_rounded),
                        label: Text(widget.photo
                            ? "Use phone's camera"
                            : "Record with phone's camera"),
                      ),
                      const SizedBox(height: 4),
                      if (!_starting)
                        TextButton(
                            onPressed: _tryAgain,
                            child: const Text('Try again')),
                    ] else if (!_starting &&
                        problem.blocked != null &&
                        !kIsWeb) ...[
                      FilledButton.icon(
                        key: const Key('storyCameraSettings'),
                        onPressed: _openSettings,
                        icon: const Icon(Icons.settings_rounded),
                        label: const Text('Open Settings'),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                          onPressed: _tryAgain, child: const Text('Try again')),
                    ] else if (!_starting)
                      FilledButton(
                        onPressed: _tryAgain,
                        child: const Text('Try again'),
                      ),
                    if (StoryCameraScreen.canChooseFile) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        key: const Key('storyChooseFile'),
                        onPressed: _chooseFile,
                        icon: const Icon(Icons.upload_file_rounded),
                        label: Text(widget.photo
                            ? 'Choose a photo instead'
                            : 'Choose a video file instead'),
                      ),
                    ],
                  ]),
                ),
              ),
            ),

          // ---- bottom: record ----
          if (camera != null && _problem == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: AnimatedBuilder(
                animation: _recording,
                builder: (context, _) {
                  final seconds =
                      _recording.value * _maxLength.inMilliseconds / 1000;
                  return Column(children: [
                    Text(
                      widget.photo
                          ? 'Tap to take a photo'
                          : _isRecording
                              ? '${seconds.toStringAsFixed(1)}s / '
                                  '${_maxLength.inSeconds}s'
                              : 'Tap to record · up to '
                                  '${_maxLength.inSeconds} seconds',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(color: Colors.black87, blurRadius: 6)
                          ]),
                    ),
                    const SizedBox(height: 12),
                    // the record button in the middle; a file beside it on
                    // a computer's browser
                    Row(children: [
                      const Expanded(child: SizedBox()),
                      _RecordButton(
                        recording: _isRecording,
                        progress: _recording.value,
                        photo: widget.photo,
                        onPressed: widget.photo
                            ? _snap
                            : _isRecording
                                ? (_canStop ? _stop : null)
                                : _start,
                      ),
                      Expanded(
                        child: StoryCameraScreen.canChooseFile && !_isRecording
                            ? Center(
                                child: StoryRoundButton(
                                  key: const Key('storyChooseFile'),
                                  tooltip: widget.photo
                                      ? 'Choose a photo'
                                      : 'Choose a video file',
                                  icon: Icons.upload_file_rounded,
                                  size: 52,
                                  onPressed: _chooseFile,
                                ),
                              )
                            : const SizedBox(),
                      ),
                    ]),
                  ]);
                },
              ),
            ),
        ]),
      ),
    );
  }
}

/// A friendly note on what stories are: a moment from right now. With
/// [fileToo] (a computer's browser) a short clip can be uploaded too.
class _LiveOnlyLabel extends StatelessWidget {
  const _LiveOnlyLabel({required this.fileToo});

  final bool fileToo;

  @override
  Widget build(BuildContext context) {
    final seconds = StoryService.maxLength.inSeconds;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          key: const Key('storyLiveOnly'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.auto_awesome_rounded,
                  color: HuntrColors.orange, size: 18),
              SizedBox(width: 6),
              Flexible(
                child: Text('Share a moment from right now',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ),
            ]),
            const SizedBox(height: 2),
            Text(
                fileToo
                    ? 'Record a quick clip, or upload one up to $seconds '
                        'seconds.'
                    : 'Quick and real, up to $seconds seconds.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          ]),
        ),
      ),
    );
  }
}

/// The big round button: white to start; red, with the time running round
/// it in orange, while recording. A [photo] shutter stays white.
class _RecordButton extends StatelessWidget {
  const _RecordButton(
      {required this.recording,
      required this.progress,
      this.photo = false,
      this.onPressed});

  final bool recording;
  final double progress;
  final bool photo;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: photo
            ? 'Take photo'
            : recording
                ? 'Stop recording'
                : 'Record',
        child: GestureDetector(
          key: const Key('storyRecord'),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 84,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.square(
                dimension: 84,
                child: CircularProgressIndicator(
                  value: recording ? progress : 0,
                  strokeWidth: 5,
                  color: HuntrColors.orange,
                  backgroundColor: Colors.white54,
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: recording ? 34 : 64,
                height: recording ? 34 : 64,
                decoration: BoxDecoration(
                  color: recording ? const Color(0xFFE53935) : Colors.white,
                  borderRadius: BorderRadius.circular(recording ? 8 : 32),
                ),
              ),
            ]),
          ),
        ),
      );
}

/// How to allow the camera and microphone here: in the phone's Settings for
/// the apps, in the browser's site settings on the website (each kind of
/// device says it its own way).
class _AllowSteps extends StatelessWidget {
  const _AllowSteps();

  static List<String> get steps {
    final android = defaultTargetPlatform == TargetPlatform.android;
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    if (!kIsWeb && android) {
      return const [
        'Tap Open Settings below.',
        'Go to Permissions.',
        'Allow Camera and Microphone.',
        'Come back to HUNTR.',
      ];
    }
    if (!kIsWeb && ios) {
      return const [
        'Tap Open Settings below.',
        'Turn on Camera and Microphone.',
        'Come back to HUNTR.',
      ];
    }
    if (ios) {
      return const [
        'Tap aA in the address bar.',
        'Tap Website Settings.',
        'Set Camera and Microphone to Allow.',
        'Tap Try again.',
      ];
    }
    if (android) {
      return const [
        'Tap the icon at the left of the address bar.',
        'Tap Permissions.',
        'Allow Camera and Microphone.',
        'Tap Try again.',
      ];
    }
    return const [
      'Click the camera or lock icon at the left of the address bar.',
      'Allow Camera and Microphone for this site.',
      'Click Try again (reload the page if it asks).',
    ];
  }

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('storyAllowSteps'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: [
          for (final (i, step) in steps.indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
              child: Row(children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: HuntrColors.orange,
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(step,
                        style: const TextStyle(color: Colors.white))),
              ]),
            ),
        ]),
      );
}
