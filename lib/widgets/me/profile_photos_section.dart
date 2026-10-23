import '../../flows/media_permission.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../flows/photo_upload_flow.dart';
import '../../models/models.dart';
import '../../services/huntr_backend.dart';
import '../../services/photo_cache/photo_cache.dart';
import '../../services/photo_service.dart';
import '../../services/services_scope.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../photos/photo_viewer_screen.dart';
import 'profile_photo_grid.dart';
import 'section_states.dart';
import 'settings_group.dart';

/// "Profile photos" on Me: my saved photos from the backend, with upload
/// (pick, check, crop), and a viewer to set the default, re-crop or remove.
/// The backend is the source of truth; every change reloads the list.
class ProfilePhotosSection extends StatefulWidget {
  const ProfilePhotosSection({super.key});

  @override
  State<ProfilePhotosSection> createState() => _ProfilePhotosSectionState();
}

class _ProfilePhotosSectionState extends State<ProfilePhotosSection> {
  static const _captionStyle =
      TextStyle(color: HuntrColors.muted, fontSize: 14, height: 1.4);

  PhotoService? _photos;
  PhotoCache? _cache;
  bool _loading = false;
  String? _loadError;
  bool _uploading = false;

  /// Photos being removed from the grid's quick remove buttons.
  final Set<int> _removing = {};

  /// Upload size limit from the backend.
  int? _maxUploadBytes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_photos == null) {
      _photos = ServicesScope.photosOf(context);
      _cache = ServicesScope.photoCacheOf(context)?..refresh = _refreshPhoto;
      if (_photos != null) _load();
    }
  }

  String? get _token => AppScope.read(context).sessionToken;

  /// For the cache, when a photo's link expired: reloads the list (fresh
  /// links) and returns that photo, or null when it's no longer listed.
  Future<ProfilePhoto?> _refreshPhoto(int photoId) async {
    final photos = _photos;
    final token = mounted ? _token : null;
    if (photos == null || token == null) return null;
    final list = await photos.fetchMine(token);
    _apply(list);
    for (final photo in list.photos) {
      if (photo.id == photoId) return photo;
    }
    return null;
  }

  Future<void> _load() async {
    final photos = _photos;
    final token = _token;
    if (photos == null || token == null) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      _apply(await photos.fetchMine(token));
    } on SessionRejectedException {
      _signOut();
    } catch (error) {
      if (mounted) {
        setState(() => _loadError = error is BackendException
            ? error.message
            : 'Your photos could not be loaded.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// A successful refresh: the device keeps only the listed photos.
  void _apply(ProfilePhotoList list) {
    if (!mounted) return;
    unawaited(_cache?.keepOnly(list.photos));
    _maxUploadBytes = list.maxUploadBytes;
    AppScope.read(context)
        .setProfilePhotos(list.photos, maxPhotos: list.maxPhotos);
  }

  void _signOut() {
    if (mounted) AppScope.read(context).endSession();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs a backend call with the shared error handling. True on success.
  Future<bool> _attempt(
      Future<void> Function(PhotoService photos, String token) call) async {
    final photos = _photos;
    final token = _token;
    if (photos == null || token == null) return false;
    try {
      await call(photos, token);
      return true;
    } on SessionRejectedException {
      _signOut();
    } on BackendException catch (error) {
      _say(error.message);
    } catch (_) {
      _say('Something went wrong. Please try again.');
    }
    return false;
  }

  String _limitMessage(int max) =>
      "You've reached the maximum of $max profile photos. "
      'Remove a photo before uploading another.';

  Future<void> _add() async {
    final app = AppScope.read(context);
    final max = app.maxProfilePhotos;
    if (max != null && app.profilePhotos.length >= max) {
      return _say(_limitMessage(max));
    }
    final photos = _photos!;
    final picked = await withMediaPermission(context, photos.pickFromDevice);
    if (picked == null || !mounted) return;
    final photo = await checkAndCropPhoto(context, picked,
        maxBytes: _maxUploadBytes ?? picked.bytes.length, onProblem: _say);
    if (photo == null || !mounted) return;

    setState(() => _uploading = true);
    ProfilePhoto? saved;
    final uploaded = await _attempt((photos, token) async => saved =
        await photos.upload(token,
            bytes: photo.bytes, filename: photo.filename, crop: photo.crop));
    if (mounted) setState(() => _uploading = false);
    if (uploaded) {
      // Saved on the device right away; a failure here doesn't undo the upload.
      unawaited(_cache?.load(saved!));
      await _load();
      _say('Photo added');
    }
  }

  Future<void> _open(ProfilePhoto photo) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PhotoViewerScreen(
          initialPhotoId: photo.id,
          onSetDefault: (photo) => _attempt((photos, token) async =>
              _apply(await photos.setDefault(token, photo.id))),
          onEdit: _recrop,
          onRemove: _remove,
        ),
      ));

  /// Removes the photo (record and S3) on the backend. True when it worked;
  /// a failure shows the backend's message and keeps the photo.
  Future<bool> _remove(ProfilePhoto photo) => _attempt((photos, token) async {
        final list = await photos.remove(token, photo.id);
        // Only once the backend removed it; a failed removal keeps it.
        await _cache?.retire(photo.id);
        _apply(list);
      });

  /// The grid's remove button: right away, without asking first.
  Future<void> _quickRemove(ProfilePhoto photo) async {
    if (_removing.contains(photo.id)) return;
    setState(() => _removing.add(photo.id));
    await _remove(photo);
    if (mounted) setState(() => _removing.remove(photo.id));
  }

  /// Moves a photo (the first is Main): shown right away, saved on the
  /// backend; a failure puts the photos back as they were.
  Future<void> _move(int from, int to) async {
    final app = AppScope.read(context);
    final before = app.profilePhotos;
    final moved = [...before];
    moved.insert(to, moved.removeAt(from));
    app.setProfilePhotos([
      for (final (i, p) in moved.indexed)
        ProfilePhoto(
            id: p.id,
            url: p.url,
            isDefault: i == 0,
            width: p.width,
            height: p.height),
    ], maxPhotos: app.maxProfilePhotos!);
    final saved = await _attempt((photos, token) async =>
        _apply(await photos.reorder(token, [for (final p in moved) p.id])));
    if (!saved && mounted) {
      app.setProfilePhotos(before, maxPhotos: app.maxProfilePhotos!);
    }
  }

  /// The saved crop replaces the photo under a new id; returns it, or null.
  Future<ProfilePhoto?> _recrop(ProfilePhoto photo) async {
    final crop = await cropStoredPhoto(context, photo, _cache);
    if (crop == null) return null;
    ProfilePhoto? saved;
    await _attempt((photos, token) async {
      saved = await photos.recrop(token, photo.id, crop);
      await _cache?.retire(photo.id); // the old photo is gone
    });
    final replacement = saved;
    if (replacement == null) return null;
    unawaited(_cache?.load(replacement));
    await _load();
    return replacement;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final photos = app.profilePhotos;
    final max = app.maxProfilePhotos;
    final full = max != null && photos.length >= max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          max == null
              ? 'PROFILE PHOTOS'
              : 'PROFILE PHOTOS · ${photos.length}/$max',
          trailing: max == null
              ? null
              : PhotoCountDots(used: photos.length, max: max),
        ),
        const SizedBox(height: 6),
        const Text(
            'Everyone can see these on your profile. Tap one to view, crop, '
            'remove or make it your main photo. Hold and drag to rearrange; '
            'the first one is your main photo.',
            style: _captionStyle),
        const SizedBox(height: 14),
        if (_photos == null)
          const Text('Managing photos needs the Huntr server.',
              style: _captionStyle)
        else if (_loading && max == null)
          const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_loadError != null && max == null)
          LoadFailedCard(
            title: "Couldn't load your photos",
            message: _loadError!,
            onRetry: _load,
            messageKey: const Key('profilePhotosError'),
            retryKey: const Key('profilePhotosRetry'),
          )
        else ...[
          ProfilePhotoGrid(
            photos: photos,
            canAdd: !full,
            uploading: _uploading,
            onOpen: _open,
            onAdd: _add,
            onRemove: _quickRemove,
            onMove: _move,
            removing: _removing,
          ),
        ],
      ],
    );
  }
}
