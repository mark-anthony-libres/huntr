import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import '../services/huntr_backend.dart';
import '../services/photo_cache/photo_cache.dart';
import '../services/photo_service.dart';
import '../widgets/photos/photo_crop_screen.dart';
import '../widgets/photos/photo_edits.dart';
import '../widgets/photos/photo_file_check.dart';

/// A picked photo, checked and cropped by the user, ready to upload.
class CroppedPhoto {
  const CroppedPhoto(
      {required this.bytes, required this.filename, required this.crop});
  final Uint8List bytes;
  final String filename;
  final PhotoCrop crop;
}

/// Checks a picked photo (type, size, readable), then lets the user crop it
/// (and draw on it or blur parts of it: baked in before it's uploaded, so
/// the original never leaves the device). Null when it's refused
/// ([onProblem] gets the reason) or the crop is cancelled. Shared by
/// profile photos and album photos.
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
  final result =
      await Navigator.of(context).push<PhotoCropResult>(MaterialPageRoute(
    builder: (_) => PhotoCropScreen(
        image: MemoryImage(bytes), imageSize: size, editable: true),
  ));
  if (result == null) return null;
  if (result.strokes.isEmpty) {
    return CroppedPhoto(
        bytes: bytes, filename: picked.filename, crop: result.crop);
  }
  // drawn on or blurred: the edited photo (smaller if it'd be too big)
  try {
    final edited = await _edited(bytes, result.strokes, maxBytes);
    if (edited == null) {
      onProblem('The edited photo is too large. Try a smaller photo.');
      return null;
    }
    final name = picked.filename.replaceFirst(RegExp(r'\.[^.]*$'), '');
    return CroppedPhoto(
        bytes: edited, filename: '$name.png', crop: result.crop);
  } catch (error) {
    debugPrint('Photo edits not applied: $error');
    onProblem("The photo couldn't be edited. Please try again.");
    return null;
  }
}

/// What was chosen for a saved photo: its crop, and (drawn on or blurred)
/// the edited photo, uncropped, the crop still to apply.
class StoredPhotoEdit {
  const StoredPhotoEdit(this.crop, [this.edited]);
  final PhotoCrop crop;
  final Uint8List? edited;
}

/// Lets the user crop a saved photo further, draw on it or blur parts of it
/// (from its cached bytes when the device has them). Null when cancelled,
/// or when the edits can't be applied ([onProblem] gets why).
Future<StoredPhotoEdit?> editStoredPhoto(
    BuildContext context, StoredPhoto photo, PhotoCache? cache,
    {required int maxBytes,
    required void Function(String problem) onProblem}) async {
  final cached = cache?.peek(photo.id);
  final result =
      await Navigator.of(context).push<PhotoCropResult>(MaterialPageRoute(
    builder: (_) => PhotoCropScreen(
      title: 'Edit photo',
      confirmLabel: 'Save',
      editable: true,
      image: cached != null
          ? MemoryImage(cached.bytes)
          : NetworkImage(photo.imageUrl,
              webHtmlElementStrategy: WebHtmlElementStrategy.fallback),
      imageSize: Size(photo.width.toDouble(), photo.height.toDouble()),
    ),
  ));
  if (result == null) return null;
  if (result.strokes.isEmpty) return StoredPhotoEdit(result.crop);
  try {
    final bytes = (await cache?.load(photo))?.bytes ??
        (await http.get(Uri.parse(photo.imageUrl))).bodyBytes;
    final edited = await _edited(bytes, result.strokes, maxBytes);
    if (edited == null) {
      onProblem('The edited photo is too large. Try a smaller photo.');
      return null;
    }
    return StoredPhotoEdit(result.crop, edited);
  } catch (error) {
    debugPrint('Photo edits not applied: $error');
    onProblem("The photo couldn't be edited. Please try again.");
    return null;
  }
}

/// [bytes] with [strokes] baked in, smaller if it'd be over [maxBytes]
/// (null when even that is).
Future<Uint8List?> _edited(
    Uint8List bytes, List<PhotoStroke> strokes, int maxBytes) async {
  var edited = await applyPhotoEdits(bytes, strokes);
  if (edited.length > maxBytes) {
    edited = await applyPhotoEdits(bytes, strokes, maxSide: 1400);
  }
  return edited.length > maxBytes ? null : edited;
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
