import 'dart:async';

import 'package:flutter/material.dart';

import '../services/huntr_backend.dart';
import '../services/services_scope.dart';
import '../state/app_state.dart';

/// Loads my profile photos into [AppState]; the device keeps only those.
/// Returns the list, or null without a backend or a session.
Future<ProfilePhotoList?> loadMyProfilePhotos(BuildContext context) async {
  final app = AppScope.read(context);
  final photos = ServicesScope.photosOf(context);
  final cache = ServicesScope.photoCacheOf(context);
  final token = app.sessionToken;
  if (photos == null || token == null) return null;
  final list = await photos.fetchMine(token);
  unawaited(cache?.keepOnly(list.photos));
  app.setProfilePhotos(list.photos, maxPhotos: list.maxPhotos);
  return list;
}
