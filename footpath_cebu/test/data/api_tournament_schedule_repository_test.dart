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
              'startsOn': '2026-08-27',
              'isPublished': true,
              'documentUrl': 'https://storage.example/signed-schedule',
              'publishedAt': '2026-08-20T08:00:00Z',
              'updatedAt': '2026-08-26T08:00:00Z',
              'ageBrackets': [
                {
                  'id': 'bracket-1',
                  'maxAge': 12,
                  'label': 'U12',
                  'scheduledAt': '2026-08-27T05:00:00Z',
                  'squad': {
                    'id': 'squad-1',
                    'bracketId': 'bracket-1',
                    'status': 'PUBLISHED',
                    'publishedAt': '2026-08-26T08:00:00Z',
                    'entries': [
                      {
                        'id': 'entry-1',
                        'playerId': '8',
                        'playerName': 'Alex Santos',
                        'tournamentPosition': 'CM',
                      },
                    ],
                  },
                },
              ],
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
                  'ageBracketId': 'b12',
                  'ageBracketLabel': 'U12',
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
    expect(rows.single.ageBrackets.single.label, 'U12');
    expect(
      rows.single.ageBrackets.single.squad!.entries.single.playerName,
      'Alex Santos',
    );
    expect(
      rows.single.fixtures.single.status,
      TournamentFixtureStatus.scheduled,
    );
    expect(rows.single.fixtures.single.ageBracketLabel, 'U12');
    expect(rows.single.fixtures.single.opponent, 'Mandaue FC');
  });

  test('creates a document-optional tournament draft', () async {
    late http.Request captured;
    final api = AuthenticatedApiClient(
      identityProvider: () =>
          ApiIdentity(uid: 'coordinator-1', getIdToken: (_) async => 'token'),
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'id': 'schedule-2',
            'title': 'Sinulog Cup',
            'startsOn': '2026-09-20',
            'isPublished': false,
            'documentUrl': null,
            'publishedAt': null,
            'updatedAt': '2026-08-29T08:00:00Z',
            'ageBrackets': [],
            'fixtures': [],
          }),
          201,
        );
      }),
    );

    final created = await ApiTournamentScheduleRepository(
      api: api,
    ).createTournament(title: 'Sinulog Cup', startsOn: DateTime(2026, 9, 20));

    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/tournament-schedules/');
    expect(jsonDecode(captured.body), {
      'title': 'Sinulog Cup',
      'startsOn': '2026-09-20',
    });
    expect(created.isPublished, isFalse);
    expect(created.publishedAt, isNull);
  });

  test('adds a bracket with an optional division schedule', () async {
    late http.Request captured;
    final api = AuthenticatedApiClient(
      identityProvider: () =>
          ApiIdentity(uid: 'coordinator-1', getIdToken: (_) async => 'token'),
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'id': 'schedule-2',
            'title': 'Sinulog Cup',
            'startsOn': '2026-09-20',
            'isPublished': false,
            'documentUrl': null,
            'publishedAt': null,
            'updatedAt': '2026-08-29T08:00:00Z',
            'ageBrackets': [
              {
                'id': 'bracket-8',
                'maxAge': 8,
                'label': 'U8',
                'scheduledAt': '2026-09-20T08:00:00Z',
              },
            ],
            'fixtures': [],
          }),
          201,
        );
      }),
    );

    final saved = await ApiTournamentScheduleRepository(api: api).addAgeBracket(
      'schedule-2',
      maxAge: 8,
      scheduledAt: DateTime.utc(2026, 9, 20, 8),
    );

    expect(captured.url.path, '/api/tournament-schedules/schedule-2/brackets/');
    expect(jsonDecode(captured.body), {
      'maxAge': 8,
      'scheduledAt': '2026-09-20T08:00:00.000Z',
    });
    expect(saved.ageBrackets.single.maxAge, 8);
  });
}
