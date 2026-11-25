import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:record/record.dart';

import '../../services/huntr_backend.dart' show LocalUpload;
import '../../theme.dart';
import 'voice_bubble.dart' show VoiceBubble, VoiceWaveform, newVoicePlayer;
import 'voice_file_io.dart' if (dart.library.js_interop) 'voice_file_web.dart';

/// The longest voice message (the backend allows the same).
const voiceMessageMaxLength = Duration(minutes: 5);

/// Makes the recorder a recording bar uses (tests put a fake one here).
AudioRecorder Function() newVoiceRecorder = AudioRecorder.new;

/// Shorter than this isn't sent (a tap on the mic and Send at once).
const _shortest = Duration(milliseconds: 700);

/// How many bars the recording shows when I listen to it (as its bubble).
const _reviewBars = 48;

/// "1:05"
String voiceTime(Duration d) {
  final seconds = d.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Where I am with a voice message.
enum _Stage { starting, recording, paused, listening }

/// Where the message box was, while I record a voice message: how long so
/// far and the sound as it comes in, then Delete, Pause / Resume, Stop
/// (to listen to it first) and Send. Recording starts at once (asking for
/// the microphone the first time) and stops at [voiceMessageMaxLength],
/// sending what was recorded. Stopped, I can play it (tap or drag its
/// waveform to jump) before sending or deleting it.
class VoiceRecorderBar extends StatefulWidget {
  const VoiceRecorderBar({
    super.key,
    required this.onSend,
    required this.onDone,
    required this.onProblem,
  });

  /// The recording, ready to send.
  final void Function(LocalUpload recording) onSend;

  /// Back to the message box (after sending or deleting).
  final VoidCallback onDone;

  /// Something to tell me (no microphone, or recording failed).
  final void Function(String message) onProblem;

  @override
  State<VoiceRecorderBar> createState() => _VoiceRecorderBarState();
}

class _VoiceRecorderBarState extends State<VoiceRecorderBar>
    with SingleTickerProviderStateMixin {
  late final AudioRecorder _recorder = newVoiceRecorder();
  final _clock = Stopwatch();
  Timer? _tick;
  StreamSubscription<Amplitude>? _levels;

  /// The latest loudness readings (0-1), newest last, for the live bars.
  final _heard = <double>[];

  /// Every reading (for the recording's waveform when I listen to it).
  final _all = <double>[];

  /// How many readings came in (the live list keeps only the latest).
  int _readings = 0;
  String _extension = 'm4a';
  _Stage _stage = _Stage.starting;
  bool _finishing = false;

  /// The stopped recording, while I listen to it (until sent or deleted).
  String? _path;
  Duration _length = Duration.zero;
  List<int> _waveform = const [];

  /// Listening: the player, and where it is (moved on every frame between
  /// its reports, like a bubble's).
  AudioPlayer? _player;
  final _playerEvents = <StreamSubscription<Object?>>[];
  bool _playing = false;
  bool _played = false;
  Duration _reported = Duration.zero;
  final _sinceReport = Stopwatch();
  /// Made the first time I listen (none when I never do).
  Ticker? _frames;

  bool get _recording =>
      _stage == _Stage.recording || _stage == _Stage.paused;

  Duration get _position {
    if (!_playing) return _reported;
    final now = _reported + _sinceReport.elapsed;
    return now > _length ? _length : now;
  }

  @override
  void initState() {
    super.initState();
    // a voice message playing would be recorded too
    VoiceBubble.pauseAll();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      if (!await _recorder.hasPermission()) {
        widget.onProblem(
            'Allow HUNTR to use your microphone to record a voice message.');
        widget.onDone();
        return;
      }
      // browsers that can't record AAC (Chrome, Firefox) record Opus in WebM;
      // the backend converts either
      var encoder = AudioEncoder.aacLc;
      if (kIsWeb && await _recorder.isEncoderSupported(AudioEncoder.opus)) {
        encoder = AudioEncoder.opus;
      }
      _extension = encoder == AudioEncoder.opus ? 'webm' : 'm4a';
      await _recorder.start(
          RecordConfig(encoder: encoder, numChannels: 1, bitRate: 64000),
          path: await newRecordingPath(_extension));
      if (!mounted) {
        await _recorder.cancel();
        return;
      }
      _clock.start();
      _levels = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen((a) {
        if (_stage != _Stage.recording) return;
        // dBFS: about -45 (quiet) to 0 (loud)
        final level = ((a.current + 45) / 45).clamp(0.05, 1.0);
        setState(() {
          _heard.add(level);
          _all.add(level);
          _readings++;
          if (_heard.length > 80) _heard.removeAt(0);
        });
      });
      _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (_clock.elapsed >= voiceMessageMaxLength) {
          unawaited(_send());
        } else {
          setState(() {});
        }
      });
      setState(() => _stage = _Stage.recording);
    } catch (error) {
      debugPrint('Recording failed to start: $error');
      widget.onProblem("Your microphone couldn't be used. Please try again.");
      widget.onDone();
    }
  }

  Future<void> _stopListening() async {
    _clock.stop();
    _tick?.cancel();
    await _levels?.cancel();
  }

  Duration get _recorded => _clock.elapsed > voiceMessageMaxLength
      ? voiceMessageMaxLength
      : _clock.elapsed;

  Future<void> _togglePause() async {
    if (!_recording || _finishing) return;
    try {
      if (_stage == _Stage.paused) {
        await _recorder.resume();
        _clock.start();
        setState(() => _stage = _Stage.recording);
      } else {
        await _recorder.pause();
        _clock.stop();
        setState(() => _stage = _Stage.paused);
      }
    } catch (error) {
      debugPrint('Recording not paused or resumed: $error');
      widget.onProblem("The recording couldn't be paused. Please try again.");
    }
  }

  /// Stops recording, to listen to it before sending.
  Future<void> _stopToListen() async {
    if (!_recording || _finishing) return;
    setState(() => _finishing = true);
    final length = _recorded;
    await _stopListening();
    try {
      final path = await _recorder.stop();
      if (path == null || length < _shortest) {
        await discardRecording(path);
        widget.onDone();
        return;
      }
      if (!mounted) {
        await discardRecording(path);
        return;
      }
      setState(() {
        _path = path;
        _length = length;
        _waveform = _shape(_all);
        _stage = _Stage.listening;
        _finishing = false;
      });
    } catch (error) {
      debugPrint('Recording failed: $error');
      widget.onProblem("The recording couldn't be saved. Please try again.");
      widget.onDone();
    }
  }

  /// The readings as a bubble's waveform: [_reviewBars] bars, 0-100 (the
  /// loudest reading in each part).
  static List<int> _shape(List<double> readings) {
    if (readings.isEmpty) return const [];
    return [
      for (var bar = 0; bar < _reviewBars; bar++)
        () {
          final from = bar * readings.length ~/ _reviewBars;
          final to = math.max(
              from + 1, (bar + 1) * readings.length ~/ _reviewBars);
          return (readings.sublist(from, math.min(to, readings.length)).reduce(
                      math.max) *
                  100)
              .round();
        }()
    ];
  }

  AudioPlayer _readyPlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = newVoicePlayer();
    _playerEvents
      ..add(player.onPositionChanged.listen((p) {
        if (!mounted) return;
        setState(() {
          _reported = p;
          _sinceReport
            ..reset()
            ..start();
        });
      }))
      ..add(player.onPlayerStateChanged.listen((state) {
        if (mounted) setState(() => _setPlaying(state == PlayerState.playing));
      }))
      ..add(player.onPlayerComplete.listen((_) {
        if (!mounted) return;
        setState(() {
          _setPlaying(false);
          _played = false;
          _reported = Duration.zero;
        });
      }));
    return _player = player;
  }

  void _setPlaying(bool playing) {
    if (_playing == playing) return;
    if (!playing) _reported = _position;
    _playing = playing;
    if (playing) {
      _sinceReport
        ..reset()
        ..start();
      final frames = _frames ??= createTicker((_) => setState(() {}));
      if (!frames.isActive) unawaited(frames.start());
    } else {
      _sinceReport.stop();
      if (_frames?.isActive ?? false) _frames!.stop();
    }
  }

  /// Plays or pauses the stopped recording.
  Future<void> _toggleListen({Duration? from}) async {
    final path = _path;
    if (path == null || _finishing) return;
    final player = _readyPlayer();
    try {
      if (_playing && from == null) {
        await player.pause();
      } else if (_played && from == null) {
        await player.resume();
      } else if (_played) {
        await player.seek(from!);
        if (!_playing) await player.resume();
      } else {
        // the recording is still on the phone (in the browser, a blob URL)
        await player.play(kIsWeb ? UrlSource(path) : DeviceFileSource(path),
            position: from ?? _reported);
        _played = true;
      }
    } catch (error) {
      debugPrint('Recording not played: $error');
      widget.onProblem("The recording couldn't be played.");
    }
  }

  void _seek(double fraction) {
    final to = _length * fraction.clamp(0.0, 1.0);
    setState(() {
      _reported = to;
      _sinceReport
        ..reset()
        ..start();
    });
    unawaited(_toggleListen(from: to));
  }

  Future<void> _send() async {
    if (_finishing || _stage == _Stage.starting) return;
    setState(() => _finishing = true);
    final listened = _stage == _Stage.listening;
    final length = listened ? _length : _recorded;
    try {
      String? path;
      if (listened) {
        await _player?.stop();
        path = _path;
        _path = null;
      } else {
        await _stopListening();
        path = await _recorder.stop();
      }
      if (path == null || length < _shortest) {
        await discardRecording(path);
        widget.onDone();
        return;
      }
      final bytes = await takeRecording(path);
      widget.onSend(LocalUpload(
          bytes: bytes,
          filename: 'voice.$_extension',
          isVideo: false,
          voiceLength: length));
    } catch (error) {
      debugPrint('Recording failed: $error');
      widget.onProblem("The recording couldn't be saved. Please try again.");
    }
    widget.onDone();
  }

  Future<void> _delete() async {
    if (_finishing) return;
    _finishing = true;
    if (_stage == _Stage.listening) {
      await _player?.stop();
      final path = _path;
      _path = null;
      await discardRecording(path);
    } else {
      await _stopListening();
      try {
        await _recorder.cancel();
      } catch (_) {}
    }
    widget.onDone();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _levels?.cancel();
    _frames?.dispose();
    for (final s in _playerEvents) {
      unawaited(s.cancel());
    }
    unawaited(_player?.dispose());
    unawaited(discardRecording(_path));
    unawaited(_recorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listening = _stage == _Stage.listening;
    final elapsed = listening ? _length : _clock.elapsed;
    final left = voiceMessageMaxLength - elapsed;
    final lastMinute = _recording && left <= const Duration(minutes: 1);
    final used = (elapsed.inMilliseconds / voiceMessageMaxLength.inMilliseconds)
        .clamp(0.0, 1.0);
    final live = _stage == _Stage.recording && !_finishing;
    final position = _position;
    final status = switch (_stage) {
      _Stage.starting => 'Starting the microphone…',
      _ when lastMinute => '${voiceTime(left)} left',
      _Stage.recording => 'Recording',
      _Stage.paused => 'Paused',
      _Stage.listening => 'Listen before sending',
    };
    return Padding(
      key: const Key('voiceRecorder'),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Container(
        decoration: BoxDecoration(
          color: HuntrColors.surfaceHigh,
          borderRadius: BorderRadius.circular(26),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // what's happening, and how long
          Row(children: [
            SizedBox.square(
              dimension: 22,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: switch (_stage) {
                  _Stage.paused => Icon(Icons.pause_rounded,
                      key: const ValueKey('paused'),
                      size: 20,
                      color: HuntrColors.muted),
                  _Stage.listening => Icon(Icons.headphones_rounded,
                      key: const ValueKey('listening'),
                      size: 19,
                      color: HuntrColors.orange),
                  _ => _RecordingDot(key: const ValueKey('dot'), on: live),
                },
              ),
            ),
            const SizedBox(width: 10),
            Text(voiceTime(listening && _played ? position : elapsed),
                key: const Key('voiceElapsed'),
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    fontFeatures: [FontFeature.tabularFigures()])),
            if (listening)
              Text(' / ${voiceTime(_length)}',
                  style: TextStyle(
                      color: HuntrColors.muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            const Spacer(),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(status,
                  key: ValueKey(status.endsWith('left') ? 'left' : status),
                  style: TextStyle(
                      color: lastMinute ? HuntrColors.coral : HuntrColors.muted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 10),
          // the sound: coming in while recording; the whole recording (tap
          // or drag to jump) while listening
          SizedBox(
            height: 40,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: listening
                  ? LayoutBuilder(
                      key: const ValueKey('review'),
                      builder: (_, box) => GestureDetector(
                        key: const Key('voiceReviewWaveform'),
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) =>
                            _seek(d.localPosition.dx / box.maxWidth),
                        onHorizontalDragUpdate: (d) =>
                            _seek(d.localPosition.dx / box.maxWidth),
                        child: CustomPaint(
                          size: Size(box.maxWidth, 40),
                          painter: VoiceWaveform(
                              waveform: _waveform,
                              played: _length == Duration.zero
                                  ? 0
                                  : (position.inMilliseconds /
                                          _length.inMilliseconds)
                                      .clamp(0.0, 1.0),
                              playing: _playing,
                              showHead: _played || position > Duration.zero,
                              clock: _sinceReport.elapsedMilliseconds +
                                  _reported.inMilliseconds,
                              on: HuntrColors.orange,
                              off: HuntrColors.muted.withValues(alpha: 0.45)),
                        ),
                      ),
                    )
                  : _stage == _Stage.starting
                      ? const SizedBox.expand(key: ValueKey('starting'))
                      : _LiveSound(
                          key: const ValueKey('sound'),
                          levels: _heard,
                          readings: _readings,
                          running: live,
                          color: _stage == _Stage.paused
                              ? HuntrColors.muted
                              : HuntrColors.orange),
            ),
          ),
          const SizedBox(height: 8),
          // how much of the 5 minutes is used
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: used,
              minHeight: 3,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              color: lastMinute ? HuntrColors.coral : HuntrColors.orange,
            ),
          ),
          const SizedBox(height: 6),
          // Delete · Pause / Resume (or Play / Pause) · Stop · Send
          Row(children: [
            IconButton(
              key: const Key('voiceDelete'),
              tooltip: 'Delete recording',
              onPressed: _finishing ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
              color: HuntrColors.muted,
            ),
            const Spacer(),
            _RoundButton(
              key: const Key('voicePause'),
              tooltip: switch (_stage) {
                _Stage.paused => 'Resume recording',
                _Stage.listening => _playing ? 'Pause' : 'Play recording',
                _ => 'Pause recording',
              },
              icon: switch (_stage) {
                _Stage.paused => Icons.mic_rounded,
                _Stage.listening =>
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                _ => Icons.pause_rounded,
              },
              color: _stage == _Stage.paused ? HuntrColors.coral : null,
              onPressed: _finishing || _stage == _Stage.starting
                  ? null
                  : listening
                      ? () => unawaited(_toggleListen())
                      : _togglePause,
            ),
            // stop, to listen first (not once stopped)
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: listening
                  ? const SizedBox(height: 48)
                  : Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: _RoundButton(
                        key: const Key('voiceStop'),
                        tooltip: 'Stop and listen',
                        icon: Icons.stop_rounded,
                        onPressed: _recording && !_finishing
                            ? _stopToListen
                            : null,
                      ),
                    ),
            ),
            const Spacer(),
            AnimatedScale(
              scale: _stage == _Stage.starting ? 0.85 : 1,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              child: IconButton.filled(
                key: const Key('voiceSend'),
                tooltip: 'Send voice message',
                style: IconButton.styleFrom(
                  backgroundColor: HuntrColors.orange,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor:
                      HuntrColors.orange.withValues(alpha: 0.45),
                  minimumSize: const Size(48, 48),
                ),
                onPressed: _stage != _Stage.starting && !_finishing
                    ? _send
                    : null,
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _finishing
                      ? const SizedBox.square(
                          key: ValueKey('sending'),
                          dimension: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.send_rounded, key: ValueKey('send')),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// A round control in the recording panel (its icon turning when it
/// changes).
class _RoundButton extends StatelessWidget {
  const _RoundButton(
      {super.key,
      required this.tooltip,
      required this.icon,
      required this.onPressed,
      this.color});

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  /// The icon's colour (white when null).
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.08),
          minimumSize: const Size(48, 48),
        ),
        onPressed: onPressed,
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, a) => RotationTransition(
              turns: Tween(begin: 0.75, end: 1.0).animate(a),
              child: ScaleTransition(scale: a, child: child)),
          child: Icon(icon, key: ValueKey(icon), color: color),
        ),
      );
}

/// The red dot, with a ring rippling out of it while recording.
class _RecordingDot extends StatefulWidget {
  const _RecordingDot({super.key, required this.on});

  final bool on;

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 22,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) {
            final t = widget.on ? _pulse.value : 0.0;
            return CustomPaint(
                painter: _DotPainter(t, widget.on, HuntrColors.coral));
          },
        ),
      );
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.t, this.on, this.color);

  final double t;
  final bool on;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    if (on) {
      // the ring: out from the dot, fading
      canvas.drawCircle(
          c,
          5 + 6 * t,
          Paint()
            ..color = color.withValues(alpha: 0.55 * (1 - t))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
    // the dot: a little bigger on the beat
    final beat = on ? 1 + 0.12 * (1 - (2 * t - 1).abs()) : 1.0;
    canvas.drawCircle(c, 5 * beat,
        Paint()..color = on ? color : color.withValues(alpha: 0.4));
  }

  @override
  bool shouldRepaint(_DotPainter old) => old.t != t || old.on != on;
}

/// The sound as it comes in: bars flowing in from the right (each new one
/// rising as it arrives), fading out on the left.
class _LiveSound extends StatefulWidget {
  const _LiveSound(
      {super.key,
      required this.levels,
      required this.readings,
      required this.running,
      required this.color});

  final List<double> levels;

  /// How many readings came in so far (a new one slides in).
  final int readings;
  final bool running;
  final Color color;

  @override
  State<_LiveSound> createState() => _LiveSoundState();
}

class _LiveSoundState extends State<_LiveSound>
    with SingleTickerProviderStateMixin {
  /// How long a new bar takes to slide in.
  static const _arrive = Duration(milliseconds: 120);

  late final Ticker _frames = createTicker((_) => setState(() {}));
  final _sinceNew = Stopwatch()..start();
  int _count = 0;

  @override
  void initState() {
    super.initState();
    if (widget.running) _frames.start();
  }

  @override
  void didUpdateWidget(_LiveSound old) {
    super.didUpdateWidget(old);
    // a new reading came in
    if (widget.readings != _count) {
      _count = widget.readings;
      _sinceNew
        ..reset()
        ..start();
    }
    if (widget.running && !_frames.isActive) _frames.start();
    if (!widget.running && _frames.isActive) _frames.stop();
  }

  @override
  void dispose() {
    _frames.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fresh = (_sinceNew.elapsedMicroseconds / _arrive.inMicroseconds)
        .clamp(0.0, 1.0);
    return ShaderMask(
      // fade out on the left
      shaderCallback: (rect) => const LinearGradient(
        colors: [Colors.transparent, Colors.white],
        stops: [0, 0.12],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: ClipRect(
        child: CustomPaint(
          size: const Size.fromHeight(30),
          painter: _LiveBars(
              widget.levels, widget.color, Curves.easeOut.transform(fresh)),
        ),
      ),
    );
  }
}

class _LiveBars extends CustomPainter {
  _LiveBars(this.levels, this.color, this.fresh);

  final List<double> levels;
  final Color color;

  /// How far the newest bar has come in (0-1).
  final double fresh;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 3.0;
    const width = 3.0;
    const step = width + gap;
    final count = (size.width / step).ceil() + 1;
    final shown =
        levels.length > count ? levels.sublist(levels.length - count) : levels;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width;
    // everything slides left by one step as a new bar comes in
    var x = size.width - width / 2 + step * (1 - fresh);
    var newest = true;
    for (final level in shown.reversed) {
      if (x < -width) break;
      final rise = newest ? fresh : 1.0;
      final h = (size.height * level * rise).clamp(3.0, size.height);
      canvas.drawLine(Offset(x, (size.height - h) / 2),
          Offset(x, (size.height + h) / 2), paint);
      x -= step;
      newest = false;
    }
    // not reached yet (the first seconds): low, faint bars to the left edge,
    // so the strip is full from the start
    paint.color = color.withValues(alpha: 0.25);
    for (; x >= -width; x -= step) {
      canvas.drawLine(Offset(x, size.height / 2 - 1.5),
          Offset(x, size.height / 2 + 1.5), paint);
    }
  }

  @override
  bool shouldRepaint(_LiveBars old) => true;
}
