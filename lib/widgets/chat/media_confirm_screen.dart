import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../theme.dart';
import 'picked_video_io.dart'
    if (dart.library.js_interop) 'picked_video_web.dart';

/// A photo or video just taken with the camera, to check before sending.
/// Pops 'send', 'retake' (take another), or nothing (drop it).
class MediaConfirmScreen extends StatefulWidget {
  const MediaConfirmScreen(
      {super.key,
      required this.bytes,
      required this.path,
      required this.isVideo});

  final List<int> bytes;

  /// Where the capture is on this device (a video plays from it).
  final String path;
  final bool isVideo;

  @override
  State<MediaConfirmScreen> createState() => _MediaConfirmScreenState();
}

class _MediaConfirmScreenState extends State<MediaConfirmScreen> {
  VideoPlayerController? _player;
  bool _videoFailed = false;

  @override
  void initState() {
    super.initState();
    if (!widget.isVideo) return;
    final player = _player = pickedVideoController(widget.path);
    player.addListener(_changed);
    player.initialize().then((_) {
      if (mounted) setState(() {});
    }, onError: (Object _) {
      if (mounted) setState(() => _videoFailed = true);
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _player?.removeListener(_changed);
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.isVideo ? 'Send this video?' : 'Send this photo?'),
        leading: IconButton(
          tooltip: 'Discard',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Center(
              child: !widget.isVideo
                  ? InteractiveViewer(
                      child: Image.memory(Uint8List.fromList(widget.bytes),
                          key: const Key('capturePreview')))
                  : _videoFailed
                      ? const _VideoPlaceholder()
                      : player == null || !player.value.isInitialized
                          ? const CircularProgressIndicator()
                          : GestureDetector(
                              onTap: () => player.value.isPlaying
                                  ? player.pause()
                                  : player.play(),
                              child: AspectRatio(
                                aspectRatio: player.value.aspectRatio,
                                child: Stack(fit: StackFit.expand, children: [
                                  VideoPlayer(player),
                                  if (!player.value.isPlaying)
                                    const Center(
                                        child: Icon(
                                            Icons.play_circle_fill_rounded,
                                            size: 72,
                                            color: Colors.white70)),
                                ]),
                              ),
                            ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('retakeCapture'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      minimumSize: const Size(48, 52),
                      shape: const StadiumBorder()),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retake'),
                  onPressed: () => Navigator.of(context).pop('retake'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      gradient: HuntrColors.accentGradient,
                      borderRadius: BorderRadius.all(Radius.circular(30))),
                  child: FilledButton.icon(
                    key: const Key('sendCapture'),
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(48, 52)),
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Send'),
                    onPressed: () => Navigator.of(context).pop('send'),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.videocam_rounded, size: 64, color: Colors.white54),
      SizedBox(height: 12),
      Text('Video recorded. A preview isn’t available here.',
          style: TextStyle(color: Colors.white70)),
    ]);
  }
}
