import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:huntr/main.dart';
import 'package:huntr/models/models.dart';
import 'package:huntr/services/huntr_backend.dart';
import 'package:huntr/services/photo_cache/photo_cache_store.dart';
import 'package:huntr/services/photo_cache/photo_cache.dart';
import 'package:huntr/services/photo_service.dart';
import 'package:huntr/state/app_state.dart';
import 'package:huntr/widgets/photos/photo_crop_screen.dart';
import 'package:huntr/widgets/photos/photo_file_check.dart';
import 'package:huntr/widgets/photos/cached_photo_image.dart';

ProfilePhoto _photo(int id, {bool isDefault = false}) => ProfilePhoto(
      id: id,
      url: 'https://photos.test/$id.webp',
      isDefault: isDefault,
      width: 1080,
      height: 1080,
    );

const _gifBytes = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0, 0, 0, 0];

/// The backend, faked: keeps the photo list and records every call.
class _FakePhotos extends PhotoService {
  _FakePhotos(int count) {
    photos = [for (var i = 1; i <= count; i++) _photo(i, isDefault: i == 1)];
  }

  final int max = 6;
  late List<ProfilePhoto> photos;
  Object? failLoadWith;
  Object? failRemoveWith;
  PickedPhoto? toPick;
  final List<String> calls = [];

  ProfilePhotoList get _list => ProfilePhotoList(
      photos: photos, maxPhotos: max, maxUploadBytes: 10 << 20);

  @override
  Future<ProfilePhotoList> fetchMine(String token) async {
    calls.add('list');
    final failure = failLoadWith;
    if (failure != null) {
      failLoadWith = null;
      throw failure;
    }
    return _list;
  }

  @override
  Future<PickedPhoto?> pickFromDevice() async => toPick;

  @override
  Future<ProfilePhoto> upload(String token,
      {required List<int> bytes,
      required String filename,
      required PhotoCrop crop}) async {
    calls.add('upload');
    throw UnimplementedError();
  }

  @override
  Future<ProfilePhotoList> setDefault(String token, int photoId) async {
    calls.add('default $photoId');
    photos = [
      for (final photo in photos)
        _photo(photo.id, isDefault: photo.id == photoId)
    ]..sort((a, b) => a.isDefault ? -1 : (b.isDefault ? 1 : a.id - b.id));
    return _list;
  }

  /// Like the backend: the crop is a new photo (new id) in the old one's place.
  @override
  Future<ProfilePhoto> recrop(String token, int photoId, PhotoCrop crop) async {
    calls.add('recrop $photoId');
    final old = photos.firstWhere((photo) => photo.id == photoId);
    final replacement = _photo(100 + photoId, isDefault: old.isDefault);
    photos = [
      for (final photo in photos) photo.id == photoId ? replacement : photo
    ];
    return replacement;
  }

  @override
  Future<ProfilePhotoList> remove(String token, int photoId) async {
    calls.add('remove $photoId');
    final failure = failRemoveWith;
    if (failure != null) throw failure;
    photos = photos.where((photo) => photo.id != photoId).toList();
    return _list;
  }
}

Future<AppState> _openMe(WidgetTester tester, _FakePhotos photos,
    {PhotoCache? cache}) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final state = AppState(onSessionEnd: cache?.clear)
    ..startSession('token')
    ..completeOnboarding(name: 'Marky', age: 21, lookingFor: {LookingFor.chat});
  await tester
      .pumpWidget(HuntrApp(state: state, photos: photos, photoCache: cache));
  await _settle(tester, decodes: cache != null);
  await tester.tap(find.text('Me'));
  await _settle(tester, decodes: cache != null);
  return state;
}

/// Like pumpAndSettle; with [decodes], also gives cached photos the real
/// time they need to decode (until then a spinner keeps animating).
Future<void> _settle(WidgetTester tester, {bool decodes = false}) async {
  if (!decodes) {
    await tester.pumpAndSettle();
    return;
  }
  for (var i = 0; i < 6; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  group('gallery', () {
    testWidgets('shows the photos and count from the backend', (tester) async {
      final state = await _openMe(tester, _FakePhotos(2));
      expect(find.text('PROFILE PHOTOS · 2/6'), findsOneWidget);
      expect(find.byKey(const Key('profilePhoto-1')), findsOneWidget);
      expect(find.byKey(const Key('addProfilePhoto')), findsOneWidget);
      expect(state.defaultPhoto?.id, 1);
    });

    testWidgets('a full gallery hides Add photo', (tester) async {
      await _openMe(tester, _FakePhotos(6));
      expect(find.text('PROFILE PHOTOS · 6/6'), findsOneWidget);
      expect(find.byKey(const Key('addProfilePhoto')), findsNothing);
    });

    testWidgets('a failed load can be retried', (tester) async {
      final photos = _FakePhotos(1)
        ..failLoadWith =
            const BackendException('Could not reach the Huntr server.');
      await _openMe(tester, photos);
      expect(find.text('Could not reach the Huntr server.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('profilePhotosRetry')));
      await tester.pumpAndSettle();
      expect(find.text('PROFILE PHOTOS · 1/6'), findsOneWidget);
    });

    testWidgets('a GIF is refused before uploading', (tester) async {
      final photos = _FakePhotos(1)
        ..toPick = const PickedPhoto(bytes: _gifBytes, filename: 'fun.jpg');
      await _openMe(tester, photos);
      await tester.tap(find.byKey(const Key('addProfilePhoto')));
      await tester.pumpAndSettle();
      expect(
          find.text(
              "GIFs aren't supported. Please choose a JPEG, PNG or WebP photo."),
          findsOneWidget);
      expect(photos.calls, isNot(contains('upload')));
    });
  });

  group('quick remove', () {
    testWidgets('removes right away, without asking', (tester) async {
      final photos = _FakePhotos(3);
      await _openMe(tester, photos);
      await tester.tap(find.descendant(
          of: find.byKey(const Key('removeProfilePhoto-2')),
          matching: find.byType(IconButton)));
      await tester.pumpAndSettle();
      expect(find.text('Remove this photo?'), findsNothing);
      expect(photos.calls, contains('remove 2'));
      expect(find.byKey(const Key('profilePhoto-2')), findsNothing);
      expect(find.text('PROFILE PHOTOS · 2/6'), findsOneWidget);
    });

    testWidgets('a failure says so and keeps the photo', (tester) async {
      const message = 'Unable to delete this photo. Please try again.';
      final photos = _FakePhotos(2)
        ..failRemoveWith = const BackendException(message);
      await _openMe(tester, photos);
      await tester.tap(find.descendant(
          of: find.byKey(const Key('removeProfilePhoto-1')),
          matching: find.byType(IconButton)));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(find.byKey(const Key('profilePhoto-1')), findsOneWidget);
      expect(find.text('PROFILE PHOTOS · 2/6'), findsOneWidget);
    });
  });

  group('viewer', () {
    Future<void> openPhoto(WidgetTester tester, int id) async {
      await tester.tap(find.byKey(Key('profilePhoto-$id')));
      await tester.pumpAndSettle();
    }

    String position(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('photoViewerPosition'))).data!;

    testWidgets('opens full screen on the tapped photo with the three actions',
        (tester) async {
      await _openMe(tester, _FakePhotos(3));
      await openPhoto(tester, 2);
      expect(position(tester), '2 / 3');
      expect(find.text('Set as default'), findsOneWidget);
      expect(find.text('Edit / Crop'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      // full screen: the viewer covers the Me screen
      expect(find.byKey(const Key('photoViewerPages')), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('photoViewerPages'))),
          tester.view.physicalSize / tester.view.devicePixelRatio);
    });

    testWidgets('swiping moves between photos', (tester) async {
      await _openMe(tester, _FakePhotos(3));
      await openPhoto(tester, 1);
      expect(position(tester), '1 / 3');
      expect(find.byKey(const Key('photoViewerMain')), findsOneWidget);
      await tester.fling(find.byKey(const Key('photoViewerPages')),
          const Offset(-600, 0), 1500);
      await tester.pumpAndSettle();
      expect(position(tester), '2 / 3');
      expect(find.byKey(const Key('photoViewerMain')), findsNothing);
      await tester.fling(find.byKey(const Key('photoViewerPages')),
          const Offset(600, 0), 1500);
      await tester.pumpAndSettle();
      expect(position(tester), '1 / 3');
    });

    testWidgets('arrows move between photos too', (tester) async {
      await _openMe(tester, _FakePhotos(2));
      await openPhoto(tester, 1);
      expect(find.byTooltip('Previous photo'), findsNothing);
      await tester.tap(find.byTooltip('Next photo'));
      await tester.pumpAndSettle();
      expect(position(tester), '2 / 2');
      expect(find.byTooltip('Next photo'), findsNothing);
    });

    testWidgets('setting the default saves it and keeps the viewer open',
        (tester) async {
      final photos = _FakePhotos(2);
      final state = await _openMe(tester, photos);
      await openPhoto(tester, 2);
      await tester.tap(find.byKey(const Key('photoSetDefault')));
      await tester.pumpAndSettle();
      expect(photos.calls, contains('default 2'));
      expect(state.defaultPhoto?.id, 2);
      // the same photo stays on screen, now marked Main, even though it
      // moved to the front of the list
      expect(find.byKey(const Key('photoViewerMain')), findsOneWidget);
      expect(find.text('Default photo'), findsOneWidget);
      expect(position(tester), '1 / 2');
    });

    testWidgets('the default photo cannot be set again', (tester) async {
      await _openMe(tester, _FakePhotos(2));
      await openPhoto(tester, 1);
      final button = tester
          .widget<InkWell>(find.descendant(
              of: find.byKey(const Key('photoSetDefault')),
              matching: find.byType(InkWell)))
          .onTap;
      expect(button, isNull);
      expect(find.text('Default photo'), findsOneWidget);
    });

    testWidgets('removing asks first, then frees a slot', (tester) async {
      final photos = _FakePhotos(2);
      await _openMe(tester, photos);
      await openPhoto(tester, 2);
      await tester.tap(find.byKey(const Key('photoRemove')));
      await tester.pumpAndSettle();
      expect(find.text('Remove this photo?'), findsOneWidget);
      expect(find.text('This action cannot be undone.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('photoRemoveConfirm')));
      await tester.pumpAndSettle();
      expect(photos.calls, contains('remove 2'));
      // the remaining photo is shown; closing returns to the updated count
      expect(position(tester), '1 / 1');
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('PROFILE PHOTOS · 1/6'), findsOneWidget);
    });

    testWidgets('removing the last photo closes the viewer', (tester) async {
      final photos = _FakePhotos(1);
      await _openMe(tester, photos);
      await openPhoto(tester, 1);
      await tester.tap(find.byKey(const Key('photoRemove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('photoRemoveConfirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('photoViewerPages')), findsNothing);
      expect(find.text('PROFILE PHOTOS · 0/6'), findsOneWidget);
    });

    testWidgets('a failed removal says so and keeps the photo', (tester) async {
      const message = 'Unable to delete this photo. Please try again.';
      final photos = _FakePhotos(2)
        ..failRemoveWith = const BackendException(message);
      final state = await _openMe(tester, photos);
      await openPhoto(tester, 2);
      await tester.tap(find.byKey(const Key('photoRemove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('photoRemoveConfirm')));
      await tester.pumpAndSettle();
      expect(photos.calls, contains('remove 2'));
      expect(find.text(message), findsOneWidget);
      // still open on the same photo, and still in the list
      expect(position(tester), '2 / 2');
      expect(state.profilePhotos.map((photo) => photo.id), [1, 2]);
    });

    testWidgets('cancelling remove keeps the photo', (tester) async {
      final photos = _FakePhotos(2);
      await _openMe(tester, photos);
      await openPhoto(tester, 2);
      await tester.tap(find.byKey(const Key('photoRemove')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(photos.calls, isNot(contains('remove 2')));
    });
  });

  group('device cache', () {
    // A real 4x4 WebP, as the backend stores them.
    final webp = base64Decode(
        'UklGRjgAAABXRUJQVlA4ICwAAABwAQCdASoEAAQAAUAmJaACdAF1AAD+694v/SbP/6TZ//SbPkkZ2rY+uwAAAA==');

    ({PhotoCache cache, MemoryPhotoCacheStore store}) newCache() {
      final store = MemoryPhotoCacheStore();
      return (
        cache: PhotoCache(
            store: store,
            client: MockClient((_) async => http.Response.bytes(webp, 200))),
        store: store,
      );
    }

    String position(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('photoViewerPosition'))).data!;

    Future<void> settle(WidgetTester tester) => _settle(tester, decodes: true);

    testWidgets('a failed removal keeps the photo on the device',
        (tester) async {
      final (:cache, :store) = newCache();
      final photos = _FakePhotos(2)
        ..failRemoveWith = const BackendException(
            'Unable to delete this photo. Please try again.');
      await _openMe(tester, photos, cache: cache);
      await settle(tester);
      expect(store.photos.keys, unorderedEquals([1, 2]));
      await tester.tap(find.byKey(const Key('profilePhoto-2')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('photoRemove')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('photoRemoveConfirm')));
      await settle(tester);
      expect(store.photos.keys, unorderedEquals([1, 2]));
      expect(cache.peek(2), isNotNull);
    });

    testWidgets('a removal takes the photo off the device', (tester) async {
      final (:cache, :store) = newCache();
      await _openMe(tester, _FakePhotos(2), cache: cache);
      await settle(tester);
      await tester.tap(find.byKey(const Key('profilePhoto-2')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('photoRemove')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('photoRemoveConfirm')));
      await settle(tester);
      expect(store.photos.keys, [1]);
    });

    testWidgets('after a crop the viewer shows the new photo, cached by its id',
        (tester) async {
      final (:cache, :store) = newCache();
      final photos = _FakePhotos(2);
      await _openMe(tester, photos, cache: cache);
      await settle(tester);
      await tester.tap(find.byKey(const Key('profilePhoto-2')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('photoEdit')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('photoCropConfirm')));
      await settle(tester);
      expect(photos.calls, contains('recrop 2'));
      // still open, on the replacement (id 102) in the same place
      expect(position(tester), '2 / 2');
      expect(
          find.byWidgetPredicate(
              (w) => w is CachedPhotoImage && w.photo.id == 102),
          findsWidgets);
      expect(store.photos.keys, unorderedEquals([1, 102])); // old id gone
    });

    testWidgets('ending the session clears the device', (tester) async {
      final (:cache, :store) = newCache();
      final state = await _openMe(tester, _FakePhotos(2), cache: cache);
      await settle(tester);
      expect(store.photos, isNotEmpty);
      state.endSession();
      await settle(tester);
      expect(store.photos, isEmpty);
    });
  });

  group('file checks', () {
    test('the real type comes from the bytes, not the name', () {
      expect(detectImageType([0xFF, 0xD8, 0xFF, 0xE0]), ImageFileType.jpeg);
      expect(
          detectImageType([0x89, 0x50, 0x4E, 0x47, 13, 10]), ImageFileType.png);
      expect(
          detectImageType(
              [...utf8.encode('RIFF'), 0, 0, 0, 0, ...utf8.encode('WEBP')]),
          ImageFileType.webp);
      expect(detectImageType(_gifBytes), ImageFileType.gif);
      expect(detectImageType(utf8.encode('BM....')), ImageFileType.other);
    });

    test('files over the limit are refused', () {
      expect(checkPickedPhoto(List.filled(11, 0xFF), maxBytes: 10),
          startsWith('The photo is too large'));
      expect(checkPickedPhoto(const [0xFF, 0xD8, 0xFF], maxBytes: 10), isNull);
    });
  });

  group('crop maths', () {
    test('an unzoomed square photo is kept whole', () {
      final crop = cropForViewport(
          displaySize: const Size(300, 300),
          viewport: 300,
          transform: Matrix4.identity());
      expect([crop.x, crop.y, crop.width, crop.height], [0, 0, 1, 1]);
    });

    test('a wide photo keeps the square shown in the frame', () {
      // 600x300 shown in a 300 frame, moved so its middle third is visible
      final transform = Matrix4.identity()..translateByDouble(-150, 0, 0, 1);
      final crop = cropForViewport(
          displaySize: const Size(600, 300),
          viewport: 300,
          transform: transform);
      expect(crop.x, closeTo(0.25, 1e-9));
      expect(crop.width, closeTo(0.5, 1e-9));
      expect(crop.height, closeTo(1, 1e-9));
    });

    test('zooming in keeps a smaller part', () {
      final transform = Matrix4.identity()
        ..translateByDouble(-150, -150, 0, 1)
        ..scaleByDouble(2, 2, 1, 1);
      final crop = cropForViewport(
          displaySize: const Size(300, 300),
          viewport: 300,
          transform: transform);
      expect([
        crop.x,
        crop.y,
        crop.width,
        crop.height
      ], [
        closeTo(0.25, 1e-9),
        closeTo(0.25, 1e-9),
        closeTo(0.5, 1e-9),
        closeTo(0.5, 1e-9)
      ]);
    });
  });

  group('API', () {
    test('uploads send the file and the crop', () async {
      await uploadMyPhoto(
        backendUrl: 'http://huntr.test/api',
        token: 'abc',
        bytes: const [0xFF, 0xD8, 0xFF],
        filename: 'me.jpg',
        crop: const PhotoCrop(x: 0.1, y: 0.2, width: 0.5, height: 0.5),
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(
              request.url.toString(), 'http://huntr.test/api/profile/photos');
          expect(request.headers['Authorization'], 'Bearer abc');
          final body = latin1.decode(request.bodyBytes);
          expect(body, contains('name="crop_x"'));
          expect(body, contains('0.1'));
          expect(body, contains('filename="me.jpg"'));
          return http.Response(
              jsonEncode({
                'data': {
                  'id': 1,
                  'url': 'u',
                  'is_default': true,
                  'width': 1080,
                  'height': 1080,
                }
              }),
              200);
        }),
      );
    });

    test("the backend's limit message is shown as it is", () {
      const message = "You've reached the maximum of 6 profile photos. "
          'Remove a photo before uploading another.';
      expect(
        uploadMyPhoto(
          backendUrl: 'http://huntr.test/api',
          token: 'abc',
          bytes: const [1],
          filename: 'x.jpg',
          crop: const PhotoCrop(x: 0, y: 0, width: 1, height: 1),
          client: MockClient(
              (_) async => http.Response(jsonEncode({'detail': message}), 409)),
        ),
        throwsA(isA<BackendException>()
            .having((e) => e.message, 'message', message)),
      );
    });
  });
}
