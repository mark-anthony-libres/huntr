import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../huntr_backend.dart' show Story;

/// How long a story file is kept (a story lasts a day) and how many at most.
const _keep = Duration(hours: 24);
const _maxFiles = 60;

/// Downloads in progress, so a story is fetched once even when it's played
/// and prefetched at the same time.
final Map<int, Future<File?>> _fetching = {};

Future<Directory> _folder() async {
  final folder =
      Directory('${(await getApplicationCacheDirectory()).path}/stories');
  return folder.create(recursive: true);
}

Future<VideoPlayerController> player(Story story) async {
  final file = await _file(story);
  return file != null
      ? VideoPlayerController.file(file)
      : VideoPlayerController.networkUrl(Uri.parse(story.videoUrl));
}

Future<void> prefetch(Story story) async {
  await _file(story);
}

/// The story's file, downloading it if needed (null if that failed).
Future<File?> _file(Story story) =>
    _fetching[story.id] ??= _download(story).whenComplete(() {
      _fetching.remove(story.id);
    });

Future<File?> _download(Story story) async {
  try {
    final folder = await _folder();
    // .mp4: iOS only plays a file it can tell is a video
    final file = File('${folder.path}/${story.id}.mp4');
    if (await file.exists()) return file;
    final response = await http.get(Uri.parse(story.videoUrl));
    if (response.statusCode != 200) return null;
    final partial = File('${file.path}.part');
    await partial.writeAsBytes(response.bodyBytes, flush: true);
    await partial.rename(file.path);
    await _tidy(folder);
    return file;
  } catch (error) {
    debugPrint('Story ${story.id} not cached: $error');
    return null;
  }
}

/// Removes files older than a day, and the oldest beyond [_maxFiles].
Future<void> _tidy(Directory folder) async {
  final files = [
    for (final entry in await folder.list().toList())
      if (entry is File) entry,
  ];
  final now = DateTime.now();
  final dated = [
    for (final file in files) (file, (await file.stat()).modified),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  for (final (i, (file, modified)) in dated.indexed) {
    if (i >= _maxFiles || now.difference(modified) > _keep) {
      await file.delete().catchError((Object _) => file);
    }
  }
}
