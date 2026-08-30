import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/data/repositories/api_attendance_repository.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('keeps an effort-only player-history record', () async {
    final api = AuthenticatedApiClient(
      identityProvider: () =>
          ApiIdentity(uid: 'player-12', getIdToken: (_) async => 'id-token'),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/attendance/');
        expect(request.url.queryParameters['player'], '12');
        return http.Response(
          '''[{"playerId":"12","sessionId":"7","status":"PRESENT","effort":75,"note":null,"updatedAt":"2026-08-30T05:45:28Z","sessionName":"Passing","coachUid":"coach-1"}]''',
          200,
        );
      }),
    );
    final repository = ApiAttendanceRepository(api: api);

    final records = await repository.fetchAttendanceForPlayer('12');

    expect(records, hasLength(1));
    expect(records.single.sessionName, 'Passing');
    expect(records.single.effort, 75);
    expect(records.single.note, isNull);
  });

  for (final status in [401, 403, 408, 422, 429, 500]) {
    test('retains HTTP $status for attendance retry policy', () async {
      final api = AuthenticatedApiClient(
        identityProvider: () =>
            ApiIdentity(uid: 'coach-1', getIdToken: (_) async => 'id-token'),
        httpClient: MockClient(
          (_) async => http.Response('{"detail":"Rejected."}', status),
        ),
      );
      final repository = ApiAttendanceRepository(api: api);

      await expectLater(
        repository.fetchAttendanceForSession('session-1'),
        throwsA(
          isA<AttendanceRepositoryException>()
              .having((error) => error.statusCode, 'statusCode', status)
              .having(
                (error) => error.isRetryable,
                'isRetryable',
                status != 422,
              ),
        ),
      );
    });
  }
}
