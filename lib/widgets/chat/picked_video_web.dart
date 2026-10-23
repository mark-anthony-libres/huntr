import 'package:video_player/video_player.dart';

/// A player for a video picked or recorded in the browser (a blob URL).
VideoPlayerController pickedVideoController(String path) =>
    VideoPlayerController.networkUrl(Uri.parse(path));
