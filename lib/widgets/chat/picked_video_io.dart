import 'dart:io';

import 'package:video_player/video_player.dart';

/// A player for a video picked or recorded on this device (a file path).
VideoPlayerController pickedVideoController(String path) =>
    VideoPlayerController.file(File(path));
