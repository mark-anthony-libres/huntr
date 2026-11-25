import 'package:http/http.dart' as http;

/// In the browser the recorder keeps the recording itself (a blob URL), so
/// no path is needed.
Future<String> newRecordingPath(String extension) async => '';

/// The recording's bytes, from its blob URL.
Future<List<int>> takeRecording(String path) async =>
    (await http.get(Uri.parse(path))).bodyBytes;

/// Nothing to delete: the browser frees the blob with the page.
Future<void> discardRecording(String? path) async {}
