import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/huntr_backend.dart';
import '../state/messaging_state.dart';

/// A chat photo or video, opened. Opening starts a viewing session on the
/// backend, which serves the media only while it's open (heartbeats keep
/// it). The recipient's countdown is paused while they view, so nothing
/// closes or stops here; leaving ends the session (the countdown then
/// starts) and drops the media from memory. Nothing is saved on the device.
class ChatMediaViewerScreen extends StatefulWidget {
  const ChatMediaViewerScreen({super.key, required this.message});

  final ChatMessage message;

  @override
  State<ChatMediaViewerScreen> createState() => _ChatMediaViewerScreenState();
}

class _ChatMediaViewerScreenState extends State<ChatMediaViewerScreen> {
  MediaAccess? _access;
  String? _error;
  bool _expired = false;
  VideoPlayerController? _player;
  Timer? _heartbeat;
  MessagingState? _messaging;

  bool get _isVideo => widget.message.attachment!.isVideo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    final messaging = _messaging = MessagingScope.read(context)!;
    setState(() {
      _error = null;
      _expired = false;
    });
    try {
      final access = await messaging.openMedia(widget.message);
      if (!mounted || access == null) return;
      setState(() => _access = access);
      _heartbeat = Timer.periodic(
          access.view.heartbeat, (_) => messaging.viewHeartbeat(access.view));
      if (access.isVideo) _play(access.url);
    } on MediaExpiredException {
      if (mounted) setState(() => _expired = true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is BackendException
            ? error.message
            : 'Check your connection and try again.');
      }
    }
  }

  void _play(String url) {
    final player = _player = VideoPlayerController.networkUrl(Uri.parse(url));
    player.addListener(_changed);
    player.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      player.play();
    }, onError: (Object _) {
      if (mounted) setState(() => _error = 'This video could not be played.');
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Leaving: ends the session (the countdown starts), stops the video and
  /// removes the photo from memory.
  void _forget() {
    _heartbeat?.cancel();
    final access = _access;
    if (access != null) {
      unawaited(_messaging?.endView(access.view, widget.message));
      if (!access.isVideo) unawaited(NetworkImage(access.url).evict());
    }
    _player?.removeListener(_changed);
    _player?.dispose();
    _player = null;
    _access = null;
  }

  @override
  void dispose() {
    _forget();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final access = _access;
    final player = _player;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(_isVideo ? 'Video' : 'Photo'),
        actions: [
          if (access != null && access.view.countdownPaused)
            const _PausedNote(),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: _expired
              ? _Message(
                  key: const Key('viewerExpired'),
                  icon: Icons.timer_off_outlined,
                  text: _isVideo
                      ? 'This video has expired.'
                      : 'This photo has expired.',
                )
              : _error != null
                  ? _Message(
                      icon: Icons.error_outline_rounded,
                      text: _error!,
                      action: TextButton(
                          onPressed: _open, child: const Text('Try again')),
                    )
                  : access == null
                      ? const CircularProgressIndicator()
                      : !access.isVideo
                          ? InteractiveViewer(
                              child: Image.network(access.url,
                                  key: const Key('viewerImage'),
                                  webHtmlElementStrategy:
                                      WebHtmlElementStrategy.fallback,
                                  loadingBuilder: (context, child, progress) =>
                                      progress == null
                                          ? child
                                          : const CircularProgressIndicator(),
                                  errorBuilder: (context, error, stack) =>
                                      const _Message(
                                          icon: Icons.broken_image_outlined,
                                          text:
                                              'This photo could not be loaded.')),
                            )
                          : player == null || !player.value.isInitialized
                              ? const CircularProgressIndicator()
                              : GestureDetector(
                                  key: const Key('viewerVideo'),
                                  onTap: () => player.value.isPlaying
                                      ? player.pause()
                                      : player.play(),
                                  child: AspectRatio(
                                    aspectRatio: player.value.aspectRatio,
                                    child:
                                        Stack(fit: StackFit.expand, children: [
                                      VideoPlayer(player),
                                      if (!player.value.isPlaying)
                                        const Center(
                                            child: Icon(
                                                Icons.play_circle_fill_rounded,
                                                size: 72,
                                                color: Colors.white70)),
                                      Positioned(
                                        left: 12,
                                        right: 12,
                                        bottom: 8,
                                        child: VideoProgressIndicator(player,
                                            allowScrubbing: true),
                                      ),
                                    ]),
                                  ),
                                ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(
      {super.key, required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 56, color: Colors.white54),
        const SizedBox(height: 14),
        Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16)),
        if (action != null) ...[const SizedBox(height: 8), action!],
      ]),
    );
  }
}

/// The recipient's countdown is paused while they view.
class _PausedNote extends StatelessWidget {
  const _PausedNote();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(right: 16),
      child: Center(
        child: Row(key: Key('countdownPaused'), children: [
          Icon(Icons.timer_outlined, size: 18, color: Colors.white70),
          SizedBox(width: 4),
          Text('Timer starts when you close this',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
        ]),
      ),
    );
  }
}
