import 'package:image_picker/image_picker.dart';

import '../config/google_oauth_config.dart';
import '../models/models.dart';
import 'huntr_backend.dart';
import 'photo_service.dart';

/// My albums on the backend: photos (stored in S3 like profile photos) and
/// videos (converted by the backend).
class AlbumService {
  const AlbumService();

  /// Lets the user choose a photo or a video from their device. Null when
  /// they cancel.
  Future<PickedPhoto?> pickFromDevice() async {
    final file = await ImagePicker().pickMedia();
    if (file == null) return null;
    return PickedPhoto(bytes: await file.readAsBytes(), filename: file.name);
  }

  Future<AlbumList> fetchMine(String token) async => fetchMyAlbums(
      backendUrl: await GoogleOAuthConfig.loadBackendUrl(), token: token);

  Future<StoredAlbum> create(String token, String name) async => createMyAlbum(
      backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
      token: token,
      name: name);

  Future<StoredAlbum> rename(String token, int albumId, String name) async =>
      renameMyAlbum(
          backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
          token: token,
          albumId: albumId,
          name: name);

  Future<AlbumList> delete(String token, int albumId) async => deleteMyAlbum(
      backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
      token: token,
      albumId: albumId);

  Future<StoredAlbumItem> add(String token, int albumId,
          {required List<int> bytes,
          required String filename,
          PhotoCrop? crop}) async =>
      addToMyAlbum(
          backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
          token: token,
          albumId: albumId,
          bytes: bytes,
          filename: filename,
          crop: crop);

  Future<StoredAlbumItem> recrop(
          String token, int albumId, int itemId, PhotoCrop crop) async =>
      recropInMyAlbum(
          backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
          token: token,
          albumId: albumId,
          itemId: itemId,
          crop: crop);

  /// All the album's item ids, in the new order.
  Future<StoredAlbum> reorder(
          String token, int albumId, List<int> itemIds) async =>
      reorderMyAlbum(
          backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
          token: token,
          albumId: albumId,
          itemIds: itemIds);

  Future<StoredAlbum> remove(String token, int albumId, int itemId) async =>
      removeFromMyAlbum(
          backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
          token: token,
          albumId: albumId,
          itemId: itemId);
}

/// One of my backend albums, as the album screens show it.
Album albumFromStored(StoredAlbum album) => Album(
    id: '${album.id}',
    name: album.name,
    photos: [for (final item in album.items) AlbumPhoto.stored(item)]);
