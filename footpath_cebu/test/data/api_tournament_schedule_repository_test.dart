import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/data/repositories/api_tournament_schedule_repository.dart';
import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('reads the club tournament schedule and structured fixtures', () async {
    late http.Request captured;
    final api = AuthenticatedApiClient(
      identityProvider: () =>
          ApiIdentity(uid: 'coordinator-1', getIdToken: (_) async => 'token'),
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode([
            {
              'id': 'schedule-1',
              'title': 'Cebu Youth Cup',
              'documentUrl': 'https://storage.example/signed-schedule',
              'publishedAt': '2026-08-20T08:00:00Z',
              'updatedAt': '2026-08-26T08:00:00Z',
              'fixtures': [
                {
                  'id': 'fixture-1',
                  'scheduleId': 'schedule-1',
                  'tournament': 'Cebu Youth Cup',
                  'stage': 'Quarterfinal',
                  'opponent': 'Mandaue FC',
                  'kickoffAt': '2026-08-27T06:00:00Z',
                  'venue': 'NEUTRAL',
                  'location': 'Cebu City Sports Center',
                  'status': 'SCHEDULED',
                  'matchId': null,
                },
              ],
            },
          ]),
          200,
        );
      }),
    );

    final rows = await ApiTournamentScheduleRepository(
      api: api,
    ).fetchSchedules();

    expect(captured.method, 'GET');
    expect(captured.url.path, '/api/tournament-schedules/');
    expect(rows.single.title, 'Cebu Youth Cup');
    expect(
      rows.single.fixtures.single.status,
      TournamentFixtureStatus.scheduled,
    );
    expect(rows.single.fixtures.single.opponent, 'Mandaue FC');
  });
}
