import 'package:video_player/video_player.dart';

import '../huntr_backend.dart' show Story;

/// In a browser the video streams (it can't be kept as a file, and its
/// storage links can't be fetched from the page).
Future<VideoPlayerController> player(Story story) async =>
    VideoPlayerController.networkUrl(Uri.parse(story.videoUrl));

Future<void> prefetch(Story story) async {}
