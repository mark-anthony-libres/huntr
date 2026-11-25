import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../services/huntr_backend.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import 'voice_recorder.dart' show voiceTime;

/// Makes the player a voice bubble uses (tests put a fake one here).
AudioPlayer Function() newVoicePlayer = AudioPlayer.new;

/// The speeds the speed button goes through.
const _speeds = [1.0, 1.5, 2.0];

/// A voice message in the chat: play / pause, its waveform (tap or drag it
/// to jump there) with a playhead moving smoothly along it, its length (or
/// how far it's played), and while it's going a speed button (1×, 1.5×,
/// 2×). Mine shows its upload progress while sending. One plays at a time:
/// starting one pauses the other. One I received and haven't played (on
/// this device) has an orange play button and a dot. When one ends, the
/// voice message right after it ([nextVoiceId]) plays.
class VoiceBubble extends StatefulWidget {
  const VoiceBubble(
      {super.key, required this.message, required this.link, this.nextVoiceId});

  final ChatMessage message;

  /// A fresh link to the recording (null when it can't be had).
  final Future<({String url, Duration lasts})?> Function() link;

  /// The message right after this one, when it's a voice message too.
  final int? nextVoiceId;

  /// Stops whichever is playing (e.g. when I start recording).
  static void pauseAll() =>
      unawaited(_VoiceBubbleState._playing?._player?.pause());

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble>
    with TickerProviderStateMixin {
  /// The bubble playing now, if any.
  static _VoiceBubbleState? _playing;

  /// The bubbles on screen, by their message's id (to play the next one).
  static final _shown = <int, _VoiceBubbleState>{};

  AudioPlayer? _player;
  final _subscriptions = <StreamSubscription<Object?>>[];
  String? _url;
  DateTime? _urlUntil;

  /// Where the player last said it was, and when: between its (coarse)
  /// reports the playhead is moved on every frame from there.
  Duration _reported = Duration.zero;
  final _sinceReport = Stopwatch();
  late final Ticker _frames = createTicker((_) => setState(() {}));

  /// The play / pause icon's turn.
  late final AnimationController _icon = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 220));

  double _speed = 1;
  bool _started = false;
  bool _isPlaying = false;
  bool _loading = false;
  bool _failed = false;

  /// Played here since it was shown (the app remembers it too).
  bool _listened = false;

  ChatMessage get m => widget.message;

  @override
  void initState() {
    super.initState();
    _show();
  }

  @override
  void didUpdateWidget(VoiceBubble old) {
    super.didUpdateWidget(old);
    // mine gets its id once sent
    if (old.message.id != m.id) _show();
  }

  void _show() {
    final id = m.id;
    if (id != null) _shown[id] = this;
  }

  /// One I received and haven't played on this device.
  bool get _unplayed {
    final id = m.id;
    if (m.fromMe || id == null || _listened) return false;
    final app = AppScope.maybeRead(context);
    return app != null && !app.voicePlayed(id);
  }

  Duration get _length =>
      m.voice?.duration ?? m.upload?.voiceLength ?? Duration.zero;

  /// Where the playhead is now.
  Duration get _position {
    if (!_isPlaying) return _reported;
    final moved = _sinceReport.elapsed * _speed;
    final now = _reported + moved;
    return now > _length ? _length : now;
  }

  @override
  void dispose() {
    if (_playing == this) _playing = null;
    _shown.removeWhere((_, bubble) => bubble == this);
    _frames.dispose();
    _icon.dispose();
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    unawaited(_player?.dispose());
    super.dispose();
  }

  void _report(Duration position) {
    _reported = position;
    _sinceReport
      ..reset()
      ..start();
  }

  void _setPlaying(bool playing) {
    if (_isPlaying == playing) return;
    // freeze the playhead where it is before stopping the clock
    if (!playing) _reported = _position;
    _isPlaying = playing;
    if (playing) {
      _sinceReport
        ..reset()
        ..start();
      if (!_frames.isActive) _frames.start();
      _icon.forward();
    } else {
      _sinceReport.stop();
      if (_frames.isActive) _frames.stop();
      _icon.reverse();
    }
  }

  AudioPlayer _ready() {
    final existing = _player;
    if (existing != null) return existing;
    final player = newVoicePlayer();
    _subscriptions
      ..add(player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _report(p));
      }))
      ..add(player.onPlayerStateChanged.listen((state) {
        if (mounted) setState(() => _setPlaying(state == PlayerState.playing));
      }))
      ..add(player.onPlayerComplete.listen((_) {
        if (!mounted) return;
        setState(() {
          _setPlaying(false);
          _started = false;
          _reported = Duration.zero;
        });
        if (_playing == this) _playing = null;
        _playNext();
      }));
    return _player = player;
  }

  /// The voice message right after this one, from its start (brought into
  /// view).
  void _playNext() {
    final next = _shown[widget.nextVoiceId];
    if (next == null || !next.mounted) return;
    unawaited(Scrollable.ensureVisible(next.context,
        alignment: 0.5, duration: const Duration(milliseconds: 300)));
    unawaited(next._play(from: Duration.zero));
  }

  /// A link that's still good (a new one when it's about to run out).
  Future<String?> _link() async {
    final until = _urlUntil;
    if (_url != null &&
        until != null &&
        DateTime.now().isBefore(until.subtract(const Duration(seconds: 30)))) {
      return _url;
    }
    final fresh = await widget.link();
    if (fresh == null) return null;
    _url = fresh.url;
    _urlUntil = DateTime.now().add(fresh.lasts);
    return _url;
  }

  Future<void> _toggle() async {
    if (_isPlaying) {
      await _player?.pause();
      return;
    }
    await _play(from: _started ? null : _reported);
  }

  /// Plays (from [from], or on from where it paused).
  Future<void> _play({Duration? from}) async {
    if (m.id == null || _loading) return;
    // the one playing before stops
    final other = _playing;
    if (other != null && other != this) await other._player?.pause();
    _playing = this;
    final player = _ready();
    if (_started && from == null) {
      await player.resume();
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final url = await _link();
      if (url == null) throw StateError('no link');
      await player.setPlaybackRate(_speed);
      await player.play(UrlSource(url), position: from);
      _started = true;
      if (!m.fromMe && mounted) {
        setState(() => _listened = true);
        AppScope.maybeRead(context)?.markVoicePlayed(m.id!);
      }
    } catch (error) {
      debugPrint('Voice message not played: $error');
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _seek(double fraction) async {
    if (m.id == null || _length == Duration.zero) return;
    final to = _length * fraction.clamp(0.0, 1.0);
    setState(() => _report(to));
    if (_started) {
      await _player?.seek(to);
      if (!_isPlaying) await _player?.resume();
    } else {
      await _play(from: to);
    }
  }

  Future<void> _nextSpeed() async {
    final next = _speeds[(_speeds.indexOf(_speed) + 1) % _speeds.length];
    setState(() {
      // the playhead goes on from here at the new speed
      _report(_position);
      _speed = next;
    });
    await _player?.setPlaybackRate(next);
  }

  @override
  Widget build(BuildContext context) {
    final me = m.fromMe;
    final upload = m.upload;
    final sending = m.pending && upload != null && !m.failed;
    final ink = me ? Colors.black : Colors.white;
    final unplayed = _unplayed;
    final faint = me
        ? Colors.black.withValues(alpha: 0.3)
        : HuntrColors.muted.withValues(alpha: 0.55);
    final position = _position;
    final played = _length.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / _length.inMilliseconds).clamp(0.0, 1.0);
    final going = _started || position > Duration.zero;
    final waveform = m.voice?.waveform ?? const <int>[];
    final id = m.id ?? m.clientId;
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: AnimatedContainer(
        key: Key('voiceBubble-$id'),
        duration: const Duration(milliseconds: 220),
        // longer ones are a little wider (as wide as 310 from a minute)
        width: math.min(
            MediaQuery.sizeOf(context).width * 0.8,
            250 + 60 * math.min(1, _length.inMilliseconds / 60000)),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(10, 10, 18, 10),
        decoration: BoxDecoration(
          gradient: me ? HuntrColors.accentGradient : null,
          color: me ? null : HuntrColors.surfaceHigh,
          borderRadius: BorderRadius.circular(28),
          // a soft glow while it plays
          boxShadow: _isPlaying
              ? [
                  BoxShadow(
                      color:
                          HuntrColors.orange.withValues(alpha: me ? 0.45 : 0.3),
                      blurRadius: 22,
                      spreadRadius: -2)
                ]
              : const [],
        ),
        child: Row(children: [
          _PlayButton(
            key: Key('voicePlay-$id'),
            me: me,
            ink: ink,
            sending: sending,
            progress: upload?.progress ?? 0,
            loading: _loading,
            failed: _failed,
            playing: _isPlaying,
            unplayed: unplayed,
            icon: _icon,
            onPressed: m.id == null || _loading ? null : _toggle,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // the waveform: tap or drag to jump there
                LayoutBuilder(
                  builder: (_, box) => GestureDetector(
                    key: Key('voiceWaveform-$id'),
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _seek(d.localPosition.dx / box.maxWidth),
                    onHorizontalDragUpdate: (d) =>
                        _seek(d.localPosition.dx / box.maxWidth),
                    child: CustomPaint(
                      size: Size(box.maxWidth, 30),
                      painter: VoiceWaveform(
                          waveform: waveform,
                          played: played,
                          playing: _isPlaying,
                          showHead: going && !sending,
                          clock: _sinceReport.elapsedMilliseconds +
                              _reported.inMilliseconds,
                          on: ink,
                          off: faint),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // its time, and the speed once it's going (the same height
                // either way, so the bubble doesn't jump)
                SizedBox(
                  height: 20,
                  child: Row(children: [
                    // not played yet: a dot before its length
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: unplayed
                          ? Container(
                              key: Key('voiceUnplayed-$id'),
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                  color: HuntrColors.orange,
                                  shape: BoxShape.circle),
                            )
                          : const SizedBox.shrink(),
                    ),
                    Text(voiceTime(going ? position : _length),
                        key: Key('voiceTime-$id'),
                        style: TextStyle(
                            color: ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                    if (going)
                      Text(' / ${voiceTime(_length)}',
                          style: TextStyle(
                              color: me
                                  ? Colors.black.withValues(alpha: 0.55)
                                  : HuntrColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                    const Spacer(),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, a) => FadeTransition(
                          opacity: a,
                          child: ScaleTransition(scale: a, child: child)),
                      child: going
                          ? _SpeedButton(
                              key: Key('voiceSpeed-$id'),
                              speed: _speed,
                              ink: ink,
                              me: me,
                              onTap: _nextSpeed,
                            )
                          // a voice message: a small mic
                          : Icon(Icons.mic_rounded,
                              key: const ValueKey('mic'),
                              size: 15,
                              color: unplayed ? HuntrColors.orange : faint),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// The round play / pause button: the icon turns between the two; a ring
/// fills while mine uploads; a spinner while it loads.
class _PlayButton extends StatelessWidget {
  const _PlayButton({
    super.key,
    required this.me,
    required this.ink,
    required this.sending,
    required this.progress,
    required this.loading,
    required this.failed,
    required this.playing,
    required this.unplayed,
    required this.icon,
    required this.onPressed,
  });

  final bool me;
  final Color ink;
  final bool sending;
  final double progress;
  final bool loading;
  final bool failed;
  final bool playing;
  final bool unplayed;
  final Animation<double> icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // mine: dark on the orange; not played yet: an orange button
    final fill = me
        ? Colors.black.withValues(alpha: 0.82)
        : unplayed
            ? HuntrColors.orange
            : Colors.white.withValues(alpha: 0.1);
    final ink = me
        ? Colors.white
        : unplayed
            ? Colors.black
            : this.ink;
    return SizedBox.square(
      dimension: 48,
      child: Material(
        color: fill,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Tooltip(
            message: sending
                ? 'Sending…'
                : playing
                    ? 'Pause'
                    : 'Play voice message',
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, a) =>
                    ScaleTransition(scale: a, child: child),
                child: sending
                    ? SizedBox.square(
                        key: const ValueKey('sending'),
                        dimension: 26,
                        child: CircularProgressIndicator(
                            key: const Key('voiceUploading'),
                            value: progress > 0 ? progress : null,
                            strokeWidth: 2.5,
                            color: ink))
                    : loading
                        ? SizedBox.square(
                            key: const ValueKey('loading'),
                            dimension: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: ink))
                        : failed
                            ? Icon(Icons.refresh_rounded,
                                key: const ValueKey('failed'), color: ink)
                            : AnimatedIcon(
                                key: const ValueKey('play'),
                                icon: AnimatedIcons.play_pause,
                                progress: icon,
                                color: ink,
                                size: 26),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "1×", "1.5×", "2×": tap for the next speed.
class _SpeedButton extends StatelessWidget {
  const _SpeedButton(
      {super.key,
      required this.speed,
      required this.ink,
      required this.me,
      required this.onTap});

  final double speed;
  final Color ink;
  final bool me;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Playback speed',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 20,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: me
                  ? Colors.black.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
                '${speed == speed.roundToDouble() ? speed.toInt() : speed}×',
                style: TextStyle(
                    color: ink,
                    fontSize: 10.5,
                    height: 1,
                    fontWeight: FontWeight.w800)),
          ),
        ),
      );
}

/// The recording's loudness as rounded bars: the played part in [on], the
/// rest in [off], a playhead dot where it is, and the bars around it
/// breathing a little while it plays. (The recording bar draws mine with it
/// when I listen before sending.)
class VoiceWaveform extends CustomPainter {
  VoiceWaveform(
      {required this.waveform,
      required this.played,
      required this.playing,
      required this.showHead,
      required this.clock,
      required this.on,
      required this.off});

  final List<int> waveform;
  final double played;
  final bool playing;
  final bool showHead;

  /// Milliseconds into the recording (drives the breathing).
  final int clock;
  final Color on;
  final Color off;

  /// A bar's width and the gap after it.
  static const _barWidth = 3.0;
  static const _gap = 3.2;

  @override
  void paint(Canvas canvas, Size size) {
    // as many bars as fit (each the loudest part of its stretch)
    final bars = math.max(8, (size.width + _gap) ~/ (_barWidth + _gap));
    final step = size.width / bars;
    final head = played * bars;
    final shapes = <RRect>[];
    for (var i = 0; i < bars; i++) {
      // a low line while mine is sending (no waveform yet)
      var value = 0.12;
      if (waveform.isNotEmpty) {
        final from = i * waveform.length ~/ bars;
        final to = math.max(from + 1, (i + 1) * waveform.length ~/ bars);
        value = waveform
                .sublist(from, math.min(to, waveform.length))
                .reduce(math.max) /
            100;
      }
      var h = math.max(3.0, size.height * (0.14 + 0.86 * value));
      if (playing) {
        // the bars at the playhead lift with the sound
        final near = math.max(0.0, 1 - (i + 0.5 - head).abs() / 2.5);
        final beat = 0.5 + 0.5 * math.sin(clock / 90 + i);
        h = math.min(size.height, h * (1 + 0.3 * near * beat));
      }
      final x = step * i + (step - _barWidth) / 2;
      shapes.add(RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - h) / 2, _barWidth, h),
          const Radius.circular(_barWidth / 2)));
    }
    final offPaint = Paint()..color = off;
    for (final bar in shapes) {
      canvas.drawRRect(bar, offPaint);
    }
    // the played part filled in smoothly, through the bar it's in
    final x = played * size.width;
    if (x > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, x, size.height));
      final onPaint = Paint()..color = on;
      for (final bar in shapes) {
        canvas.drawRRect(bar, onPaint);
      }
      canvas.restore();
    }
    if (showHead) {
      final c = Offset(x.clamp(5.0, size.width - 5), size.height / 2);
      // a soft ring round the playhead while it plays
      if (playing) {
        canvas.drawCircle(c, 9, Paint()..color = on.withValues(alpha: 0.18));
      }
      canvas.drawCircle(c, 5.5, Paint()..color = on);
    }
  }

  @override
  bool shouldRepaint(VoiceWaveform old) =>
      old.played != played ||
      old.playing != playing ||
      old.clock != clock ||
      old.showHead != showHead ||
      old.waveform != waveform ||
      old.on != on ||
      old.off != off;
}
