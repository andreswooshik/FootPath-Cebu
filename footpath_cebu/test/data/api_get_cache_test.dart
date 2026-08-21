import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/data/local/api_get_cache.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('cached GETs are isolated by Firebase owner UID', () async {
    final cache = ApiGetCache(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(cache.close);

    await cache.put(
      'user-a',
      'GET /api/players/',
      const CachedApiGet(
        statusCode: 200,
        body: '[{"id":1}]',
        headers: {'content-type': 'application/json'},
      ),
    );

    expect(
      (await cache.get('user-a', 'GET /api/players/'))?.body,
      '[{"id":1}]',
    );
    expect(await cache.get('user-b', 'GET /api/players/'), isNull);
  });

  test('cached GETs expire after the bounded 24-hour age', () async {
    var now = DateTime.utc(2026, 8, 19, 8);
    final cache = ApiGetCache(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
      now: () => now,
    );
    addTearDown(cache.close);

    await cache.put(
      'user-a',
      'GET /api/core/',
      const CachedApiGet(statusCode: 200, body: '{}', headers: {}),
    );
    expect(await cache.get('user-a', 'GET /api/core/'), isNotNull);

    now = now.add(const Duration(hours: 24));
    expect(await cache.get('user-a', 'GET /api/core/'), isNull);
  });

  test('clearOwner removes only the signed-out user cache', () async {
    final cache = ApiGetCache(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(cache.close);
    const response = CachedApiGet(statusCode: 200, body: '{}', headers: {});

    await cache.put('user-a', 'GET /api/core/', response);
    await cache.put('user-b', 'GET /api/core/', response);
    await cache.clearOwner('user-a');

    expect(await cache.get('user-a', 'GET /api/core/'), isNull);
    expect(await cache.get('user-b', 'GET /api/core/'), isNotNull);
  });
}
