// Runs in a browser only: flutter test --platform chrome test/web
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:huntr/services/photo_cache/photo_cache_store_web.dart';

void main() {
  test('IndexedDB store writes, reads, deletes and keeps only what it is told',
      () async {
    final store = IndexedDbPhotoCacheStore(
        storeName: 'profile_photos',
        databaseName:
            'huntr_photo_cache_test_${DateTime.now().microsecondsSinceEpoch}');
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    await store.clear();
    await store.write(1, bytes);
    await store.write(2, bytes);
    expect(await store.read(1), bytes);
    expect(await store.read(3), isNull);

    await store.retainOnly({1});
    expect(await store.read(2), isNull);
    expect(await store.read(1), bytes);

    await store.delete(1);
    expect(await store.read(1), isNull);

    await store.write(4, bytes);
    await store.clear();
    expect(await store.read(4), isNull);

    // a new instance (e.g. after a reload) sees what was saved
    await store.write(5, bytes);
    final reopened = IndexedDbPhotoCacheStore(
        storeName: 'profile_photos', databaseName: store.databaseName);
    expect(await reopened.read(5), bytes);
  });
}
