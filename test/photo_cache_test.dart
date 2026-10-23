import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:huntr/models/models.dart';
import 'package:huntr/services/agreement_service.dart';
import 'package:huntr/services/photo_cache/photo_cache_store.dart';
import 'package:huntr/services/photo_cache/photo_cache_store_io.dart';
import 'package:huntr/services/photo_cache/photo_cache.dart';
import 'package:huntr/services/profile_service.dart';
import 'package:huntr/services/services_scope.dart';
import 'package:huntr/widgets/photos/cached_photo_image.dart';

/// A real 4x4 WebP, so widget tests can decode it.
final _webp = base64Decode(
    'UklGRjgAAABXRUJQVlA4ICwAAABwAQCdASoEAAQAAUAmJaACdAF1AAD+694v/SbP/6TZ//SbPkkZ2rY+uwAAAA==');

ProfilePhoto _photo(int id, {String? url}) => ProfilePhoto(
    id: id,
    url: url ?? 'https://s3.test/$id.webp',
    isDefault: id == 1,
    width: 4,
    height: 4);

/// S3, faked: counts downloads per URL; [gate] holds them until completed.
class _S3 {
  final List<String> requests = [];
  Completer<void>? gate;
  http.Response Function(http.Request request) answer =
      (_) => http.Response.bytes(_webp, 200);

  late final client = MockClient((request) async {
    requests.add(request.url.toString());
    await gate?.future;
    return answer(request);
  });
}

void main() {
  late Directory directory;
  late FilePhotoCacheStore files;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('huntr_photo_cache');
    files = FilePhotoCacheStore(directory: () async => directory);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  group('file store', () {
    test('writes, reads, deletes and keeps only what it is told', () async {
      await files.write(1, _webp);
      await files.write(2, _webp);
      await File('${directory.path}/3.webp.tmp').writeAsBytes([1]);
      expect(await files.read(1), _webp);
      expect(File('${directory.path}/1.webp').existsSync(), isTrue);

      await files.retainOnly({1});
      expect(await files.read(2), isNull);
      expect(directory.listSync().map((e) => e.uri.pathSegments.last),
          ['1.webp']); // the leftover .tmp is gone too

      await files.delete(1);
      expect(await files.read(1), isNull);
      await files.write(4, _webp);
      await files.clear();
      expect(directory.existsSync(), isFalse);
    });
  });

  group('cache', () {
    test('a restart reuses saved photos without downloading', () async {
      final s3 = _S3();
      final first = PhotoCache(store: files, client: s3.client);
      expect((await first.load(_photo(1)))!.source, PhotoSource.network);
      expect(s3.requests, hasLength(1));

      // a new app start: new cache over the same files, and a new link
      final second = PhotoCache(store: files, client: s3.client);
      final shown = await second.load(_photo(1, url: 'https://s3.test/new'));
      expect(shown!.source, PhotoSource.deviceCache);
      expect(shown.bytes, _webp);
      expect(s3.requests, hasLength(1)); // nothing downloaded
    });

    test('only missing photos are downloaded', () async {
      final s3 = _S3();
      await files.write(1, _webp);
      final cache = PhotoCache(store: files, client: s3.client);
      await cache.load(_photo(1));
      await cache.load(_photo(2));
      expect(s3.requests, ['https://s3.test/2.webp']);
      // shown again (e.g. a rebuild): from memory, no download
      await cache.load(_photo(2));
      expect(s3.requests, hasLength(1));
    });

    test('one download at a time per photo', () async {
      final s3 = _S3()..gate = Completer();
      final cache = PhotoCache(store: files, client: s3.client);
      final a = cache.load(_photo(1));
      final b = cache.load(_photo(1));
      await pumpEventQueue();
      s3.gate!.complete();
      expect((await a)!.bytes, (await b)!.bytes);
      expect(s3.requests, hasLength(1));
    });

    test('a photo removed while downloading is not saved', () async {
      final s3 = _S3()..gate = Completer();
      final cache = PhotoCache(store: files, client: s3.client);
      final loading = cache.load(_photo(1));
      await pumpEventQueue();
      await cache.retire(1);
      s3.gate!.complete();
      expect(await loading, isNull);
      expect(await files.read(1), isNull);
      expect(cache.peek(1), isNull);
    });

    test('a download finishing after the session ended is not saved', () async {
      final s3 = _S3()..gate = Completer();
      final cache = PhotoCache(store: files, client: s3.client);
      await files.write(2, _webp);
      final loading = cache.load(_photo(1));
      await pumpEventQueue();
      await cache.clear();
      s3.gate!.complete();
      expect(await loading, isNull);
      expect(await files.read(1), isNull);
      expect(await files.read(2), isNull); // clear removed everything
    });

    test('an expired link is refreshed once and retried once', () async {
      final s3 = _S3()
        ..answer = (request) => request.url.path == '/fresh'
            ? http.Response.bytes(_webp, 200)
            : http.Response('expired', 403);
      final cache = PhotoCache(store: files, client: s3.client);
      var refreshes = 0;
      cache.refresh = (id) async {
        refreshes++;
        return _photo(id, url: 'https://s3.test/fresh');
      };
      expect((await cache.load(_photo(1)))!.bytes, _webp);
      expect(refreshes, 1);
      expect(s3.requests, ['https://s3.test/1.webp', 'https://s3.test/fresh']);
      expect(await files.read(1), _webp);
    });

    test('a still-failing retry gives up after one more try', () async {
      final s3 = _S3()..answer = (_) => http.Response('expired', 403);
      final cache = PhotoCache(store: files, client: s3.client)
        ..refresh = (id) async => _photo(id, url: 'https://s3.test/fresh');
      expect(await cache.load(_photo(1)), isNull);
      expect(s3.requests, hasLength(2));
    });

    test('invalid bytes are never saved and leave saved photos alone',
        () async {
      final s3 = _S3()
        ..answer = (_) => http.Response.bytes(utf8.encode('<Error/>'), 200);
      await files.write(1, _webp);
      final cache = PhotoCache(store: files, client: s3.client);
      expect(await cache.load(_photo(2)), isNull);
      expect(await files.read(2), isNull);
      expect(await files.read(1), _webp);
    });

    test('a damaged saved photo is downloaded again', () async {
      final s3 = _S3();
      await files.write(1, Uint8List.fromList([1, 2, 3]));
      final cache = PhotoCache(store: files, client: s3.client);
      expect((await cache.load(_photo(1)))!.source, PhotoSource.network);
      expect(await files.read(1), _webp);
    });

    test('keepOnly removes photos no longer listed', () async {
      final store = MemoryPhotoCacheStore()
        ..photos[1] = _webp
        ..photos[2] = _webp;
      final cache = PhotoCache(store: store, client: _S3().client);
      await cache.keepOnly([_photo(1)]);
      expect(store.photos.keys, [1]);
    });
  });

  group('cached indicator', () {
    Future<void> show(WidgetTester tester, PhotoCache cache) async {
      await tester.pumpWidget(ServicesScope(
        profiles: const ProfileService(),
        agreements: const AgreementService(),
        photoCache: cache,
        child: MaterialApp(
          home: SizedBox(
              width: 100, height: 100, child: CachedPhotoImage(_photo(1))),
        ),
      ));
      // decoding happens outside the fake clock
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
    }

    final dot = find.byKey(const Key('photoCachedDot'));

    testWidgets('shows only for a photo painted from the device cache',
        (tester) async {
      final store = MemoryPhotoCacheStore();
      final s3 = _S3();
      // first time: downloaded, so no dot even though it is now saved
      await show(tester, PhotoCache(store: store, client: s3.client));
      expect(find.byType(Image), findsOneWidget);
      expect(dot, findsNothing);
      expect(store.photos.keys, [1]);

      // next start: read from the device
      await tester.pumpWidget(const SizedBox());
      await show(tester, PhotoCache(store: store, client: s3.client));
      expect(dot, findsOneWidget);
      expect(s3.requests, hasLength(1));
    });

    testWidgets('no dot when loading fails', (tester) async {
      final s3 = _S3()..answer = (_) => http.Response('nope', 500);
      await show(tester,
          PhotoCache(store: MemoryPhotoCacheStore(), client: s3.client));
      expect(dot, findsNothing);
    });

    testWidgets('no dot while downloading', (tester) async {
      final s3 = _S3()..gate = Completer();
      await show(tester,
          PhotoCache(store: MemoryPhotoCacheStore(), client: s3.client));
      expect(dot, findsNothing);
      s3.gate!.complete();
    });
  });
}
