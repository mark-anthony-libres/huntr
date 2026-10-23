import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../theme.dart';
import '../chat/picked_video_io.dart'
    if (dart.library.js_interop) '../chat/picked_video_web.dart';

/// Frames from across a video, side by side (behind a trim bar): each a
/// muted, paused copy of the video held at its moment, as a browser can't
/// take frames out of a video otherwise.
class VideoFilmstrip extends StatefulWidget {
  const VideoFilmstrip(
      {super.key, required this.path, required this.length, this.frames = 8});

  final String path;
  final Duration length;
  final int frames;

  @override
  State<VideoFilmstrip> createState() => _VideoFilmstripState();
}

class _VideoFilmstripState extends State<VideoFilmstrip> {
  late final List<VideoPlayerController> _frames = [
    for (var i = 0; i < widget.frames; i++) pickedVideoController(widget.path)
  ];
  final Set<int> _ready = {};

  @override
  void initState() {
    super.initState();
    for (final (i, frame) in _frames.indexed) {
      // the middle of each slice of the video
      final at = widget.length * ((i + 0.5) / widget.frames);
      frame.initialize().then((_) async {
        await frame.setVolume(0);
        await frame.seekTo(at);
        if (mounted) setState(() => _ready.add(i));
      }).catchError((Object _) {}); // a missing frame stays plain
    }
  }

  @override
  void dispose() {
    for (final frame in _frames) {
      frame.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(children: [
        for (final (i, frame) in _frames.indexed)
          Expanded(
            child: ColoredBox(
              color: HuntrColors.surface,
              child: _ready.contains(i)
                  ? ClipRect(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: frame.value.size.width,
                          height: frame.value.size.height,
                          child: VideoPlayer(frame),
                        ),
                      ),
                    )
                  : const SizedBox.expand(),
            ),
          ),
      ]);
}
