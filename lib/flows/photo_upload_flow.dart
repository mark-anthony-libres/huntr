import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/huntr_backend.dart';
import '../services/photo_cache/photo_cache.dart';
import '../services/photo_service.dart';
import '../widgets/photos/photo_crop_screen.dart';
import '../widgets/photos/photo_file_check.dart';

/// A picked photo, checked and cropped by the user, ready to upload.
class CroppedPhoto {
  const CroppedPhoto(
      {required this.bytes, required this.filename, required this.crop});
  final Uint8List bytes;
  final String filename;
  final PhotoCrop crop;
}

/// Checks a picked photo (type, size, readable), then lets the user crop it.
/// Null when it's refused ([onProblem] gets the reason) or the crop is
/// cancelled. Shared by profile photos and album photos.
Future<CroppedPhoto?> checkAndCropPhoto(
  BuildContext context,
  PickedPhoto picked, {
  required int maxBytes,
  required void Function(String problem) onProblem,
}) async {
  final problem = checkPickedPhoto(picked.bytes, maxBytes: maxBytes);
  if (problem != null) {
    onProblem(problem);
    return null;
  }
  final bytes = Uint8List.fromList(picked.bytes);
  final Size size;
  try {
    size = await _imageSize(bytes);
  } catch (_) {
    onProblem("This file isn't a valid image or is damaged.");
    return null;
  }
  if (!context.mounted) return null;
  final crop = await Navigator.of(context).push<PhotoCrop>(MaterialPageRoute(
    builder: (_) => PhotoCropScreen(image: MemoryImage(bytes), imageSize: size),
  ));
  if (crop == null) return null;
  return CroppedPhoto(bytes: bytes, filename: picked.filename, crop: crop);
}

/// Lets the user crop a stored photo further, from its cached bytes when the
/// device has them. Null when cancelled.
Future<PhotoCrop?> cropStoredPhoto(
    BuildContext context, StoredPhoto photo, PhotoCache? cache) {
  final cached = cache?.peek(photo.id);
  return Navigator.of(context).push<PhotoCrop>(MaterialPageRoute(
    builder: (_) => PhotoCropScreen(
      title: 'Edit photo',
      confirmLabel: 'Save crop',
      image: cached != null
          ? MemoryImage(cached.bytes)
          : NetworkImage(photo.imageUrl,
              webHtmlElementStrategy: WebHtmlElementStrategy.fallback),
      imageSize: Size(photo.width.toDouble(), photo.height.toDouble()),
    ),
  ));
}

Future<Size> _imageSize(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final size =
      Size(frame.image.width.toDouble(), frame.image.height.toDouble());
  frame.image.dispose();
  codec.dispose();
  return size;
}
