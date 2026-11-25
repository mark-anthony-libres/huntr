import 'dart:typed_data';

import 'save_image_io.dart' if (dart.library.js_interop) 'save_image_web.dart'
    as platform;

/// Saves a PNG for the user: downloaded in a browser; on a phone, the share
/// sheet (which has Save image).
Future<void> saveImage(Uint8List png, String fileName) =>
    platform.saveImage(png, fileName);
