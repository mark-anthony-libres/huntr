import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where a new recording goes on a phone (a file of its own, deleted once
/// its bytes are read).
Future<String> newRecordingPath(String extension) async {
  final folder = await getTemporaryDirectory();
  return '${folder.path}/voice-${DateTime.now().microsecondsSinceEpoch}.$extension';
}

/// The recording's bytes, and its file deleted.
Future<List<int>> takeRecording(String path) async {
  final file = File(path);
  final bytes = await file.readAsBytes();
  try {
    await file.delete();
  } catch (_) {
    // a temporary file: the system clears it anyway
  }
  return bytes;
}

/// A recording that was thrown away.
Future<void> discardRecording(String? path) async {
  if (path == null) return;
  try {
    await File(path).delete();
  } catch (_) {}
}
