import 'package:image_picker/image_picker.dart';

import '../config/google_oauth_config.dart';
import '../models/models.dart';
import 'huntr_backend.dart';

/// A file the user picked on their device, not yet uploaded.
class PickedPhoto {
  const PickedPhoto({required this.bytes, required this.filename});
  final List<int> bytes;
  final String filename;
}

/// My profile photos on the backend (stored in S3).
class PhotoService {
  const PhotoService();

  /// Lets the user choose a photo from their device (gallery or files).
  /// Null when they cancel.
  Future<PickedPhoto?> pickFromDevice() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    return PickedPhoto(bytes: await file.readAsBytes(), filename: file.name);
  }

  Future<ProfilePhotoList> fetchMine(String token) async => fetchMyPhotos(
      backendUrl: await GoogleOAuthConfig.loadBackendUrl(), token: token);

  Future<ProfilePhoto> upload(String token,
          {required List<int> bytes,
          required String filename,
          required PhotoCrop crop}) async =>
      uploadMyPhoto(
        backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
        token: token,
        bytes: bytes,
        filename: filename,
        crop: crop,
      );

  Future<ProfilePhotoList> setDefault(String token, int photoId) async =>
      setMyDefaultPhoto(
          backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
          token: token,
          photoId: photoId);

  /// All my photo ids in the new order; the first becomes main.
  Future<ProfilePhotoList> reorder(String token, List<int> photoIds) async =>
      reorderMyPhotos(
          backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
          token: token,
          photoIds: photoIds);

  Future<ProfilePhoto> recrop(
          String token, int photoId, PhotoCrop crop) async =>
      recropMyPhoto(
          backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
          token: token,
          photoId: photoId,
          crop: crop);

  Future<ProfilePhotoList> remove(String token, int photoId) async =>
      removeMyPhoto(
          backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
          token: token,
          photoId: photoId);
}
