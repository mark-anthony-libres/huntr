import 'media_permission.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/album_service.dart';
import '../services/huntr_backend.dart';
import '../services/photo_cache/photo_cache.dart';
import '../services/services_scope.dart';
import '../state/app_state.dart';
import '../widgets/photos/photo_file_check.dart';
import 'photo_upload_flow.dart';

/// My albums on the backend. Every change goes through here: on success the
/// backend's answer updates [AppState] and the album cache (removed or
/// replaced items are retired, a refresh keeps only the listed ones); on
/// failure the backend's message is shown and nothing changes.
class MyAlbums {
  MyAlbums.of(this.context)
      : service = ServicesScope.albumsOf(context)!,
        cache = ServicesScope.photoCacheOf(context, PhotoCollection.album),
        app = AppScope.read(context);

  final BuildContext context;
  final AlbumService service;
  final PhotoCache? cache;
  final AppState app;

  void say(String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs a backend call with the shared error handling. True on success.
  Future<bool> attempt(Future<void> Function(String token) call) async {
    final token = app.sessionToken;
    if (token == null) return false;
    try {
      await call(token);
      return true;
    } on SessionRejectedException {
      app.endSession();
    } on BackendException catch (error) {
      say(error.message);
    } catch (_) {
      say('Something went wrong. Please try again.');
    }
    return false;
  }

  /// Loads my albums; throws like the backend calls do.
  Future<void> load(String token) async =>
      apply(await service.fetchMine(token));

  void apply(AlbumList list) {
    unawaited(cache?.keepOnly([
      for (final album in list.albums) ...album.items,
    ]));
    app.setMyAlbums(
      [for (final album in list.albums) albumFromStored(album)],
      AlbumLimits(
        maxAlbums: list.maxAlbums,
        maxItems: list.maxItems,
        maxPhotoBytes: list.maxPhotoBytes,
        maxVideoBytes: list.maxVideoBytes,
        maxVideoSeconds: list.maxVideoSeconds,
        maxNameLength: list.maxNameLength,
      ),
    );
  }

  /// For the cache, when a link expired: reloads (fresh links) and returns
  /// that item, or null when it's no longer listed.
  Future<StoredPhoto?> refresh(int itemId) async {
    final token = app.sessionToken;
    if (token == null) return null;
    final list = await service.fetchMine(token);
    apply(list);
    for (final album in list.albums) {
      for (final item in album.items) {
        if (item.id == itemId) return item;
      }
    }
    return null;
  }

  Future<Album?> create(String name) async {
    Album? created;
    await attempt((token) async {
      created = albumFromStored(await service.create(token, name));
      app.replaceMyAlbum(created!);
    });
    return created;
  }

  Future<bool> rename(Album album, String name) =>
      attempt((token) async => app.replaceMyAlbum(albumFromStored(
          await service.rename(token, int.parse(album.id), name))));

  Future<bool> delete(Album album) => attempt((token) async {
        final list = await service.delete(token, int.parse(album.id));
        for (final photo in album.photos) {
          await cache?.retire(photo.stored!.id);
        }
        apply(list);
      });

  /// Picks a photo (checked and cropped) or a video and adds it.
  Future<bool> add(Album album) async {
    final limits = app.albumLimits!;
    if (album.photos.length >= limits.maxItems) {
      say('This album is full. It can hold up to ${limits.maxItems} photos '
          'and videos.');
      return false;
    }
    final picked = await withMediaPermission(context, service.pickFromDevice);
    if (picked == null || !context.mounted) return false;
    final List<int> bytes;
    final String filename;
    PhotoCrop? crop;
    if (isVideoFile(picked.bytes)) {
      final problem =
          checkPickedVideo(picked.bytes, maxBytes: limits.maxVideoBytes);
      if (problem != null) {
        say(problem);
        return false;
      }
      (bytes, filename) = (picked.bytes, picked.filename);
    } else {
      final photo = await checkAndCropPhoto(context, picked,
          maxBytes: limits.maxPhotoBytes, onProblem: say);
      if (photo == null) return false;
      (bytes, filename, crop) = (photo.bytes, photo.filename, photo.crop);
    }
    return attempt((token) async {
      final item = await service.add(token, int.parse(album.id),
          bytes: bytes, filename: filename, crop: crop);
      // Saved on the device right away; a failure here doesn't undo it.
      unawaited(cache?.load(item));
      app.replaceMyAlbum(Album(
          id: album.id,
          name: album.name,
          photos: [...album.photos, AlbumPhoto.stored(item)]));
    });
  }

  /// Crops an album photo; the crop replaces it under a new id.
  Future<bool> recrop(Album album, StoredAlbumItem item) async {
    final crop = await cropStoredPhoto(context, item, cache);
    if (crop == null) return false;
    return attempt((token) async {
      final replacement =
          await service.recrop(token, int.parse(album.id), item.id, crop);
      await cache?.retire(item.id); // the old photo is gone
      unawaited(cache?.load(replacement));
      app.replaceMyAlbum(Album(id: album.id, name: album.name, photos: [
        for (final photo in album.photos)
          photo.stored?.id == item.id ? AlbumPhoto.stored(replacement) : photo
      ]));
    });
  }

  /// Moves the item at [from] to [to]: shown right away, saved on the
  /// backend; a failure puts the album back as it was.
  Future<bool> move(Album album, int from, int to) async {
    final photos = [...album.photos];
    photos.insert(to, photos.removeAt(from));
    app.replaceMyAlbum(Album(id: album.id, name: album.name, photos: photos));
    final saved = await attempt((token) async => app.replaceMyAlbum(
        albumFromStored(await service.reorder(token, int.parse(album.id),
            [for (final p in photos) p.stored!.id]))));
    if (!saved) app.replaceMyAlbum(album);
    return saved;
  }

  Future<bool> remove(Album album, StoredAlbumItem item) =>
      attempt((token) async {
        final saved = await service.remove(token, int.parse(album.id), item.id);
        // Only once the backend removed it; a failed removal keeps it.
        await cache?.retire(item.id);
        app.replaceMyAlbum(albumFromStored(saved));
      });
}
