import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/data/repositories/api_attendance_repository.dart';
import 'package:footpath_cebu/data/repositories/api_dispute_repository.dart';
import 'package:footpath_cebu/data/repositories/api_player_repository.dart';
import 'package:footpath_cebu/data/repositories/api_training_repository.dart';
import 'package:footpath_cebu/domain/repositories/training_repository.dart';
import 'package:footpath_cebu/data/repositories/api_session_confirmation_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final collectionReaders =
      <String, Future<List<Object>> Function(AuthenticatedApiClient)>{
        'squad': (api) => ApiPlayerRepository(api: api).fetchSquad(),
        'linked players': (api) =>
            ApiPlayerRepository(api: api).fetchLinkedPlayers(),
        'sessions': (api) => ApiTrainingRepository(api: api).fetchSessions(),
        'disputes': (api) => ApiDisputeRepository(api: api).fetchDisputes(),
        'confirmations': (api) => ApiSessionConfirmationRepository(
          api: api,
        ).fetchConfirmationsForPlayer('12'),
      };
  late String uid;
  setUp(() => uid = 'coach-a');
  AuthenticatedApiClient client(
    Future<http.Response> Function(http.Request) send,
  ) => AuthenticatedApiClient(
    identityProvider: () =>
        ApiIdentity(uid: uid, getIdToken: (_) async => 'token'),
    httpClient: MockClient(send),
  );

  test(
    'attendance follows pages and preserves player and unlock headers',
    () async {
      var calls = 0;
      final api = client((request) async {
        expect(request.url.queryParameters['player'], '12');
        expect(request.headers['X-Player-Unlock'], 'unlock');
        expect(request.url.queryParameters['offset'], calls == 0 ? null : '1');
        calls++;
        return http.Response(
          jsonEncode([
            {
              'playerId': '12',
              'sessionId': '$calls',
              'status': 'PRESENT',
              'updatedAt': '2026-09-10T05:00:00Z',
            },
          ]),
          200,
          headers: calls == 1 ? {'x-next-offset': '1'} : {},
        );
      });
      final records = await ApiAttendanceRepository(
        api: api,
      ).fetchAttendanceForPlayer('12', unlockToken: 'unlock');
      expect(records.map((record) => record.sessionId), ['1', '2']);
      expect(calls, 2);
    },
  );

  test('supports result envelopes and relative next links', () async {
    var calls = 0;
    final api = client((request) async {
      calls++;
      return http.Response(
        jsonEncode({
          'results': [
            {'id': calls},
          ],
          'next': calls == 1 ? '?offset=1' : null,
        }),
        200,
      );
    });
    expect(await api.getList('/api/players/'), [
      {'id': 1},
      {'id': 2},
    ]);
  });

  test('reads one bounded page without aggregating later pages', () async {
    var calls = 0;
    final api = client((request) async {
      calls++;
      expect(request.url.queryParameters, containsPair('offset', '50'));
      expect(request.url.queryParameters, containsPair('limit', '25'));
      return http.Response(
        '[{"id":51}]',
        200,
        headers: {'x-next-offset': '75'},
      );
    });

    final page = await api.getListPage(
      '/api/disputes/?status=OPEN',
      offset: 50,
      limit: 25,
    );

    expect(page.records, [
      {'id': 51},
    ]);
    expect(page.nextOffset, 75);
    expect(calls, 1);
  });

  test('training pages preserve the period filter', () async {
    final api = client((request) async {
      expect(request.url.queryParameters, {
        'period': 'PAST',
        'offset': '50',
        'limit': '25',
      });
      return http.Response(
        jsonEncode([
          {
            'id': '51',
            'title': 'Past training',
            'ageTiers': ['DEVELOPMENT'],
            'date': '2026-08-01',
            'startTime': '02:30 PM',
            'endTime': '03:45 PM',
            'location': 'Pitch',
            'focus': 'TECHNICAL',
          },
        ]),
        200,
        headers: {'x-next-offset': '75'},
      );
    });

    final page = await ApiTrainingRepository(api: api).fetchSessionPage(
      period: TrainingSessionPeriod.past,
      offset: 50,
      limit: 25,
    );

    expect(page.items.single.id, '51');
    expect(page.nextOffset, 75);
  });

  test('dispute repository maps a bounded page and its continuation', () async {
    final api = client((request) async {
      expect(request.url.queryParameters['offset'], '0');
      expect(request.url.queryParameters['limit'], '50');
      return http.Response(
        jsonEncode([
          {
            'id': 'd1',
            'category': 'ATTENDANCE',
            'status': 'OPEN',
            'summary': 'Review',
            'createdAt': '2026-09-10T05:00:00Z',
            'updatedAt': '2026-09-10T05:00:00Z',
          },
        ]),
        200,
        headers: {'x-next-offset': '50'},
      );
    });

    final page = await ApiDisputeRepository(
      api: api,
    ).fetchDisputePage(offset: 0, limit: 50);

    expect(page.items.single.id, 'd1');
    expect(page.nextOffset, 50);
  });

  for (final reader in collectionReaders.entries) {
    test('${reader.key} repository returns all pages', () async {
      var calls = 0;
      final api = client((_) async {
        calls++;
        return http.Response(
          jsonEncode([
            {
              'id': '$calls',
              'playerId': '12',
              'sessionId': '$calls',
              'category': 'ATTENDANCE',
              'status': 'OPEN',
              'summary': 'Dispute',
              'createdAt': '2026-09-10T05:00:00Z',
              'updatedAt': '2026-09-10T05:00:00Z',
              'respondedAt': '2026-09-10T05:00:00Z',
            },
          ]),
          200,
          headers: calls == 1 ? {'x-next-offset': '1'} : {},
        );
      });
      expect(await reader.value(api), hasLength(2));
      expect(calls, 2);
    });
  }

  test(
    'dispute details load the complete thread from the detail endpoint',
    () async {
      final api = client((request) async {
        expect(request.url.path, '/api/disputes/7/');
        return http.Response(
          jsonEncode({
            'id': '7',
            'category': 'ATTENDANCE',
            'status': 'OPEN',
            'summary': 'Review',
            'createdAt': '2026-09-10T05:00:00Z',
            'updatedAt': '2026-09-10T05:00:00Z',
            'responses': List.generate(
              101,
              (index) => {
                'id': '$index',
                'body': 'Response $index',
                'createdAt': '2026-09-10T05:00:00Z',
              },
            ),
          }),
          200,
        );
      });
      final dispute = await ApiDisputeRepository(api: api).fetchDispute('7');
      expect(dispute.responses, hasLength(101));
      expect(dispute.responses.first.body, 'Response 0');
    },
  );

  for (final offset in ['0', '-1', 'abc', '100001']) {
    test('rejects invalid next offset $offset', () async {
      final api = client(
        (_) async =>
            http.Response('[]', 200, headers: {'x-next-offset': offset}),
      );
      await expectLater(
        api.getList('/api/players/'),
        throwsA(isA<ApiDecodeException>()),
      );
    });
  }

  for (final body in ['null', '{}', '{"results":null}', '[1]', 'not JSON']) {
    test('rejects invalid collection $body', () async {
      final api = client((_) async => http.Response(body, 200));
      await expectLater(
        api.getList('/api/players/'),
        throwsA(isA<ApiDecodeException>()),
      );
    });
  }

  test('never returns a partial collection after a later page fails', () async {
    var calls = 0;
    final api = client(
      (_) async => ++calls == 1
          ? http.Response('[{"id":1}]', 200, headers: {'x-next-offset': '1'})
          : http.Response('{"detail":"Forbidden"}', 403),
    );
    await expectLater(
      api.getList('/api/players/'),
      throwsA(isA<ApiHttpException>()),
    );
  });

  test(
    'rejects external next links before forwarding authentication',
    () async {
      var calls = 0;
      final api = client((_) async {
        calls++;
        return http.Response(
          '{"results":[],"next":"https://other.example/api/"}',
          200,
        );
      });
      await expectLater(
        api.getList('/api/players/'),
        throwsA(isA<ApiRequestConfigurationException>()),
      );
      expect(calls, 1);
    },
  );

  test('rejects a cyclic next link', () async {
    final api = client(
      (_) async => http.Response('{"results":[],"next":"/api/players/"}', 200),
    );
    await expectLater(
      api.getList('/api/players/'),
      throwsA(isA<ApiDecodeException>()),
    );
  });

  test('discards a response when the account changes in flight', () async {
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final api = client((_) {
      started.complete();
      return response.future;
    });
    final result = api.getList('/api/players/');
    final assertion = expectLater(
      result,
      throwsA(isA<ApiSessionChangedException>()),
    );
    await started.future;
    uid = 'coach-b';
    response.complete(http.Response('[{"id":1}]', 200));
    await assertion;
  });

  test(
    'does not send a write if the account changes while obtaining a token',
    () async {
      final token = Completer<String?>();
      var calls = 0;
      final api = AuthenticatedApiClient(
        identityProvider: () =>
            ApiIdentity(uid: uid, getIdToken: (_) => token.future),
        httpClient: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      final result = api.post('/api/attendance/');
      final assertion = expectLater(
        result,
        throwsA(isA<ApiSessionChangedException>()),
      );
      uid = 'coach-b';
      token.complete('old-token');
      await assertion;
      expect(calls, 0);
    },
  );
}
