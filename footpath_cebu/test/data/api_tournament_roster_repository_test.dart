import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/data/repositories/api_tournament_roster_repository.dart';
import 'package:footpath_cebu/domain/entities/tournament_roster.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('reads privacy-safe Coach roster candidates', () async {
    late http.Request captured;
    final api = AuthenticatedApiClient(
      identityProvider: () =>
          ApiIdentity(uid: 'coach-1', getIdToken: (_) async => 'token'),
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode([
            {
              'playerId': '8',
              'playerName': 'Alex Santos',
              'currentPosition': 'CM',
              'eligibility': 'WARNING',
              'eligibilityCode': 'PENDING_INJURY',
              'eligibilityReason':
                  'Pending injury report - review before selection.',
              'selected': true,
              'tournamentPosition': 'CAM',
            },
          ]),
          200,
        );
      }),
    );

    final rows = await ApiTournamentRosterRepository(
      api: api,
    ).fetchCandidates('12');

    expect(captured.url.path, '/api/tournament-brackets/12/squad/candidates/');
    expect(rows.single.eligibility, TournamentCandidateEligibility.warning);
    expect(rows.single.tournamentPosition, 'CAM');
  });

  test('saves the Coach roster as one atomic payload', () async {
    late http.Request captured;
    final api = AuthenticatedApiClient(
      identityProvider: () =>
          ApiIdentity(uid: 'coach-1', getIdToken: (_) async => 'token'),
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'id': '3',
            'bracketId': '12',
            'status': 'DRAFT',
            'publishedAt': null,
            'entries': [
              {
                'id': '20',
                'playerId': '8',
                'playerName': 'Alex Santos',
                'tournamentPosition': 'CM',
                'availability': 'ELIGIBLE',
                'availabilityReason': 'Eligible for this bracket.',
              },
            ],
          }),
          200,
        );
      }),
    );

    final saved = await ApiTournamentRosterRepository(api: api).saveSquad(
      '12',
      const [TournamentRosterSelection(playerId: '8', position: 'CM')],
    );

    expect(captured.method, 'PUT');
    expect(captured.url.path, '/api/tournament-brackets/12/squad/');
    expect(jsonDecode(captured.body), {
      'entries': [
        {'playerId': 8, 'position': 'CM'},
      ],
    });
    expect(saved.entries.single.playerName, 'Alex Santos');
  });

  test('publishes through the dedicated Coach endpoint', () async {
    late http.Request captured;
    final api = AuthenticatedApiClient(
      identityProvider: () =>
          ApiIdentity(uid: 'coach-1', getIdToken: (_) async => 'token'),
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'id': '3',
            'bracketId': '12',
            'status': 'PUBLISHED',
            'publishedAt': '2026-08-29T09:00:00Z',
            'entries': [],
          }),
          200,
        );
      }),
    );

    final saved = await ApiTournamentRosterRepository(
      api: api,
    ).publishSquad('12');

    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/tournament-brackets/12/squad/publish/');
    expect(saved.status, TournamentSquadStatus.published);
  });
}
