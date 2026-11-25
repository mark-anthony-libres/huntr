import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

Future<void> saveImage(Uint8List png, String fileName) async {
  await SharePlus.instance.share(ShareParams(files: [
    XFile.fromData(png, mimeType: 'image/png', name: fileName),
  ], fileNameOverrides: [
    fileName
  ]));
}
