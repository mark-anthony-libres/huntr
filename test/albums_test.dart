import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:huntr/main.dart';
import 'package:huntr/models/models.dart';
import 'package:huntr/services/album_service.dart';
import 'package:huntr/services/huntr_backend.dart';
import 'package:huntr/services/photo_cache/photo_cache.dart';
import 'package:huntr/services/photo_cache/photo_cache_store.dart';
import 'package:huntr/services/photo_service.dart';
import 'package:huntr/state/app_state.dart';

/// A real 4x4 WebP, as the backend stores photos and thumbnails.
final _webp = base64Decode(
    'UklGRjgAAABXRUJQVlA4ICwAAABwAQCdASoEAAQAAUAmJaACdAF1AAD+694v/SbP/6TZ//SbPkkZ2rY+uwAAAA==');

/// The start of an MP4 file (an `ftyp` box).
final _mp4 = [0, 0, 0, 24, ...utf8.encode('ftypisom'), 0, 0, 2, 0];

StoredAlbumItem _photo(int id) => StoredAlbumItem(
    id: id,
    isVideo: false,
    url: 'https://s3.test/a$id.webp',
    width: 4,
    height: 4);

/// The backend, faked: keeps the albums and records every call.
class _FakeAlbums extends AlbumService {
  _FakeAlbums(this.albums);

  List<StoredAlbum> albums;
  int _nextId = 100;
  PickedPhoto? toPick;
  Object? failRemoveWith;
  final List<String> calls = [];

  AlbumList get _list => AlbumList(
      albums: albums,
      maxAlbums: 3,
      maxItems: 6,
      maxPhotoBytes: 10 << 20,
      maxVideoBytes: 50 << 20,
      maxVideoSeconds: 60);

  StoredAlbum _replace(int albumId, List<StoredAlbumItem> items) {
    final old = albums.firstWhere((a) => a.id == albumId);
    final album = StoredAlbum(id: albumId, name: old.name, items: items);
    albums = [for (final a in albums) a.id == albumId ? album : a];
    return album;
  }

  List<StoredAlbumItem> _items(int albumId) =>
      albums.firstWhere((a) => a.id == albumId).items;

  @override
  Future<PickedPhoto?> pickFromDevice() async => toPick;

  @override
  Future<AlbumList> fetchMine(String token) async => _list;

  @override
  Future<StoredAlbum> create(String token, String name) async {
    calls.add('create $name');
    final album = StoredAlbum(id: _nextId++, name: name, items: const []);
    albums = [...albums, album];
    return album;
  }

  @override
  Future<StoredAlbumItem> add(String token, int albumId,
      {required List<int> bytes,
      required String filename,
      PhotoCrop? crop}) async {
    calls.add('add $filename crop=${crop != null}');
    final item = StoredAlbumItem(
        id: _nextId++,
        isVideo: true,
        url: 'https://s3.test/v.mp4',
        thumbnailUrl: 'https://s3.test/v.webp',
        width: 4,
        height: 4,
        durationMs: 12000);
    _replace(albumId, [..._items(albumId), item]);
    return item;
  }

  @override
  Future<StoredAlbumItem> recrop(
      String token, int albumId, int itemId, PhotoCrop crop) async {
    calls.add('recrop $itemId');
    final item = _photo(_nextId++);
    _replace(
        albumId, [for (final i in _items(albumId)) i.id == itemId ? item : i]);
    return item;
  }

  @override
  Future<StoredAlbum> remove(String token, int albumId, int itemId) async {
    calls.add('remove $itemId');
    if (failRemoveWith != null) throw failRemoveWith!;
    return _replace(albumId, [
      for (final i in _items(albumId))
        if (i.id != itemId) i
    ]);
  }
}

class _Setup {
  _Setup(List<StoredAlbum> albums) : albums = _FakeAlbums(albums);
  final _FakeAlbums albums;
  final profileStore = MemoryPhotoCacheStore();
  final albumStore = MemoryPhotoCacheStore();
  late final client = MockClient((_) async => http.Response.bytes(_webp, 200));
  late final profileCache = PhotoCache(store: profileStore, client: client);
  late final albumCache = PhotoCache(store: albumStore, client: client);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _openMe(WidgetTester tester, _Setup setup) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final state = AppState(sampleAlbums: false)
    ..startSession('token')
    ..completeOnboarding(name: 'Marky', age: 21, lookingFor: {LookingFor.chat});
  await tester.pumpWidget(HuntrApp(
      state: state,
      photoCache: setup.profileCache,
      albums: setup.albums,
      albumCache: setup.albumCache));
  await _settle(tester);
  await tester.tap(find.text('Me'));
  await _settle(tester);
}

Future<void> _openAlbum(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await _settle(tester);
}

void main() {
  testWidgets('albums come from the backend, and the limit is shown',
      (tester) async {
    await _openMe(
        tester,
        _Setup([
          for (var i = 1; i <= 3; i++)
            StoredAlbum(id: i, name: 'Album $i', items: const []),
        ]));
    expect(find.text('MY ALBUMS · 3/3'), findsOneWidget);
    expect(find.text('Album 3'), findsOneWidget);
    expect(find.byKey(const Key('albumLimitReached')), findsOneWidget);
    expect(
        tester.widget<TextButton>(find.byKey(const Key('newAlbum'))).onPressed,
        isNull);
  });

  testWidgets('a new album is created on the backend', (tester) async {
    final setup = _Setup([]);
    await _openMe(tester, setup);
    expect(find.text('No albums yet'), findsOneWidget);
    await tester.tap(find.byKey(const Key('createFirstAlbum')));
    await _settle(tester);
    await tester.enterText(find.byKey(const Key('albumName')), 'Gym');
    await tester.tap(find.text('Save'));
    await _settle(tester);
    expect(setup.albums.calls, ['create Gym']);
    expect(find.text('No photos or videos yet.'),
        findsOneWidget); // the new album is open
  });

  testWidgets('a video is added without a crop and shown with its badge',
      (tester) async {
    final setup = _Setup([const StoredAlbum(id: 1, name: 'Weekend', items: [])])
      ..albums.toPick = PickedPhoto(bytes: _mp4, filename: 'clip.mp4');
    await _openMe(tester, setup);
    await _openAlbum(tester, 'Weekend');
    await tester.tap(find.byKey(const Key('addAlbumPhoto')));
    await _settle(tester);
    expect(setup.albums.calls, ['add clip.mp4 crop=false']);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget);
    expect(setup.albumStore.photos.keys, [100]); // its thumbnail, by item id
  });

  testWidgets('a full album says so and offers no add tile', (tester) async {
    await _openMe(
        tester,
        _Setup([
          StoredAlbum(
              id: 1,
              name: 'Weekend',
              items: [for (var i = 1; i <= 6; i++) _photo(i)]),
        ]));
    await _openAlbum(tester, 'Weekend');
    expect(find.byKey(const Key('addAlbumPhoto')), findsNothing);
    expect(find.byKey(const Key('albumFull')), findsOneWidget);
  });

  testWidgets(
      'removing an item retires its cache entry; profile photos are separate',
      (tester) async {
    final setup = _Setup([
      StoredAlbum(id: 1, name: 'Weekend', items: [_photo(1), _photo(2)]),
    ]);
    setup.profileStore.photos[1] = _webp; // a profile photo with the same id
    await _openMe(tester, setup);
    await _openAlbum(tester, 'Weekend');
    expect(setup.albumStore.photos.keys, unorderedEquals([1, 2]));
    await tester.tap(find.byKey(const Key('removeAlbumItem-album-item-1')));
    await _settle(tester);
    expect(setup.albums.calls, ['remove 1']);
    expect(setup.albumStore.photos.keys, [2]);
    expect(setup.profileStore.photos.keys, [1]); // untouched
  });

  testWidgets('a failed removal says so and changes nothing', (tester) async {
    const message = 'Unable to delete this photo. Please try again.';
    final setup = _Setup([
      StoredAlbum(id: 1, name: 'Weekend', items: [_photo(1)]),
    ])
      ..albums.failRemoveWith = const BackendException(message);
    await _openMe(tester, setup);
    await _openAlbum(tester, 'Weekend');
    await tester.tap(find.byKey(const Key('removeAlbumItem-album-item-1')));
    await _settle(tester);
    expect(find.text(message), findsOneWidget);
    expect(setup.albumStore.photos.keys, [1]);
    expect(find.byKey(const Key('albumItem-album-item-1')), findsOneWidget);
  });

  testWidgets('a crop replaces the cache entry with the new id',
      (tester) async {
    final setup = _Setup([
      StoredAlbum(id: 1, name: 'Weekend', items: [_photo(1), _photo(2)]),
    ]);
    await _openMe(tester, setup);
    await _openAlbum(tester, 'Weekend');
    await tester.tap(find.byKey(const Key('cropAlbumItem-album-item-1')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('photoCropConfirm')));
    await _settle(tester);
    expect(setup.albums.calls, ['recrop 1']);
    expect(setup.albumStore.photos.keys, unorderedEquals([2, 100]));
    // the new photo takes the old one's place
    expect(find.byKey(const Key('albumItem-album-item-100')), findsOneWidget);
  });
}
