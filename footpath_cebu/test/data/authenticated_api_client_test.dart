import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/data/local/api_get_cache.dart';
import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late ApiGetCache cache;
  late String activeUid;

  ApiIdentity identity() => ApiIdentity(
    uid: activeUid,
    getIdToken: (_) async => 'token-for-$activeUid',
  );

  setUp(() {
    activeUid = 'user-a';
    cache = ApiGetCache(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() => cache.close());

  test('a timed-out GET returns that user cached successful JSON', () async {
    final online = AuthenticatedApiClient(
      httpClient: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer token-for-user-a');
        return http.Response('{"value":"fresh"}', 200);
      }),
      cache: cache,
      identityProvider: identity,
    );
    await online.get('/api/core/', cache: true);

    final offline = AuthenticatedApiClient(
      httpClient: MockClient((_) => Completer<http.Response>().future),
      cache: cache,
      identityProvider: identity,
      timeout: const Duration(milliseconds: 10),
    );

    final response = await offline.get('/api/core/', cache: true);
    expect(response.body, '{"value":"fresh"}');
    expect(
      response.headers[AuthenticatedApiClient.cachedResponseHeader],
      'true',
    );
  });

  test(
    'a different Firebase user cannot receive the first user cache',
    () async {
      final online = AuthenticatedApiClient(
        httpClient: MockClient(
          (_) async => http.Response('{"owner":"a"}', 200),
        ),
        cache: cache,
        identityProvider: identity,
      );
      await online.get('/api/core/', cache: true);

      activeUid = 'user-b';
      final offline = AuthenticatedApiClient(
        httpClient: MockClient(
          (_) async => throw http.ClientException('offline'),
        ),
        cache: cache,
        identityProvider: identity,
      );

      await expectLater(
        offline.get('/api/core/', cache: true),
        throwsA(isA<ApiNetworkException>()),
      );
    },
  );

  test('an HTTP error never falls back to an existing cached GET', () async {
    var call = 0;
    final client = AuthenticatedApiClient(
      httpClient: MockClient((_) async {
        call += 1;
        return call == 1
            ? http.Response('{"value":"cached"}', 200)
            : http.Response(
                '{"detail":"This account may not access that club."}',
                403,
                headers: {'content-type': 'application/json'},
              );
      }),
      cache: cache,
      identityProvider: identity,
    );
    await client.get('/api/core/', cache: true);

    await expectLater(
      client.get('/api/core/', cache: true),
      throwsA(
        isA<ApiHttpException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having(
              (error) => error.message,
              'message',
              'This account may not access that club.',
            ),
      ),
    );
  });

  for (final status in [401, 500]) {
    test('HTTP $status does not fall back to a cached GET', () async {
      var call = 0;
      final client = AuthenticatedApiClient(
        httpClient: MockClient((_) async {
          call += 1;
          return call == 1
              ? http.Response('{"value":"cached"}', 200)
              : http.Response('{"detail":"server response"}', status);
        }),
        cache: cache,
        identityProvider: identity,
      );
      await client.get('/api/core/', cache: true);

      await expectLater(
        client.get('/api/core/', cache: true),
        throwsA(
          isA<ApiHttpException>().having(
            (error) => error.statusCode,
            'statusCode',
            status,
          ),
        ),
      );
    });
  }

  test(
    'a programming exception is not classified as a network error',
    () async {
      final client = AuthenticatedApiClient(
        httpClient: MockClient((_) async => throw StateError('handler bug')),
        cache: cache,
        identityProvider: identity,
      );

      await expectLater(client.get('/api/core/'), throwsA(isA<StateError>()));
    },
  );

  test(
    'malformed successful JSON is a decode error and is not cached',
    () async {
      final malformed = AuthenticatedApiClient(
        httpClient: MockClient((_) async => http.Response('<not-json>', 200)),
        cache: cache,
        identityProvider: identity,
      );
      await expectLater(
        malformed.get('/api/core/', cache: true),
        throwsA(isA<ApiDecodeException>()),
      );

      final offline = AuthenticatedApiClient(
        httpClient: MockClient(
          (_) async => throw http.ClientException('offline'),
        ),
        cache: cache,
        identityProvider: identity,
      );
      await expectLater(
        offline.get('/api/core/', cache: true),
        throwsA(isA<ApiNetworkException>()),
      );
    },
  );

  test(
    'a privacy-unlocked response is never persisted for offline use',
    () async {
      const unlockHeaders = {'X-Player-Unlock': 'short-lived-secret'};
      final online = AuthenticatedApiClient(
        httpClient: MockClient((_) async => http.Response('{"player":1}', 200)),
        cache: cache,
        identityProvider: identity,
      );
      await online.get(
        '/api/players/1/profile/',
        headers: unlockHeaders,
        cache: true,
      );

      final offline = AuthenticatedApiClient(
        httpClient: MockClient(
          (_) async => throw http.ClientException('offline'),
        ),
        cache: cache,
        identityProvider: identity,
      );
      await expectLater(
        offline.get(
          '/api/players/1/profile/',
          headers: unlockHeaders,
          cache: true,
        ),
        throwsA(isA<ApiNetworkException>()),
      );
    },
  );

  test('authenticated GET caching is disabled by default', () async {
    final online = AuthenticatedApiClient(
      httpClient: MockClient((_) async => http.Response('{"value":1}', 200)),
      cache: cache,
      identityProvider: identity,
    );
    await online.get('/api/default-no-cache/');

    final offline = AuthenticatedApiClient(
      httpClient: MockClient(
        (_) async => throw http.ClientException('offline'),
      ),
      cache: cache,
      identityProvider: identity,
    );
    await expectLater(
      offline.get('/api/default-no-cache/', cache: true),
      throwsA(isA<ApiNetworkException>()),
    );
  });

  test(
    'a network failure without a cached GET stays a network error',
    () async {
      final client = AuthenticatedApiClient(
        httpClient: MockClient(
          (_) async => throw http.ClientException('offline'),
        ),
        cache: cache,
        identityProvider: identity,
      );

      await expectLater(
        client.get('/api/not-cached/'),
        throwsA(isA<ApiNetworkException>()),
      );
    },
  );

  test('rejects an authenticated request to a different origin', () async {
    var requestCount = 0;
    final client = AuthenticatedApiClient(
      httpClient: MockClient((_) async {
        requestCount += 1;
        return http.Response('{}', 200);
      }),
      cache: cache,
      identityProvider: identity,
    );

    await expectLater(
      client.get('https://attacker.example/api/players/'),
      throwsA(isA<ApiRequestConfigurationException>()),
    );
    expect(requestCount, 0);
  });

  test('rejects a caller-supplied Authorization header', () async {
    var requestCount = 0;
    final client = AuthenticatedApiClient(
      httpClient: MockClient((_) async {
        requestCount += 1;
        return http.Response('{}', 200);
      }),
      cache: cache,
      identityProvider: identity,
    );

    await expectLater(
      client.get(
        '/api/players/',
        headers: const {'authorization': 'Bearer caller-controlled'},
      ),
      throwsA(isA<ApiRequestConfigurationException>()),
    );
    expect(requestCount, 0);
  });

  test('allows an absolute URL only when it uses the API origin', () async {
    final client = AuthenticatedApiClient(
      httpClient: MockClient((request) async {
        expect(request.url.toString(), 'http://localhost:8000/api/core/');
        expect(request.headers['authorization'], 'Bearer token-for-user-a');
        expect(request.followRedirects, isFalse);
        return http.Response('{}', 200);
      }),
      cache: cache,
      identityProvider: identity,
    );

    final response = await client.get('http://localhost:8000/api/core/');
    expect(response.statusCode, 200);
  });
}
