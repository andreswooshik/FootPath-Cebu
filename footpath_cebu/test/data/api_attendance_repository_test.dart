import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/data/repositories/api_attendance_repository.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
