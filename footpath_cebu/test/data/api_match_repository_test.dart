import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/data/repositories/api_match_repository.dart';
import 'package:footpath_cebu/domain/entities/match_performance.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'coach performance write uses URL ownership and camelCase body',
    () async {
      late http.Request captured;
      final api = AuthenticatedApiClient(
        identityProvider: () =>
            ApiIdentity(uid: 'coach-1', getIdToken: (_) async => 'id-token'),
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'id': 'perf1',
              'playerId': 'p1',
              'playerName': 'Ana Santos',
              'match': {
                'id': 'm1',
                'opponent': 'Cebu United',
                'competition': 'League',
                'playedOn': '2026-08-20',
                'venue': 'HOME',
                'ourScore': 3,
                'opponentScore': 1,
              },
              'position': 'CM',
              'starter': true,
              'minutesPlayed': 80,
              'goals': 1,
              'assists': 0,
              'shots': 2,
              'shotsOnTarget': 1,
              'passesAttempted': 30,
              'passesCompleted': 24,
              'tackles': 2,
              'interceptions': 1,
              'yellowCards': 0,
              'redCards': 0,
              'saves': 0,
              'goalsConceded': 0,
              'cleanSheet': false,
              'coachRating': 8.0,
              'notes': '',
            }),
            201,
          );
        }),
      );
      final repository = ApiMatchRepository(api: api);
      const draft = MatchPerformanceDraft(
        position: 'CM',
        starter: true,
        minutesPlayed: 80,
        goals: 1,
        assists: 0,
        shots: 2,
        shotsOnTarget: 1,
        passesAttempted: 30,
        passesCompleted: 24,
        tackles: 2,
        interceptions: 1,
        yellowCards: 0,
        redCards: 0,
        saves: 0,
        goalsConceded: 0,
        cleanSheet: false,
        coachRating: 8,
        notes: '',
      );

      final saved = await repository.savePerformance('m1', 'p1', draft);

      expect(captured.method, 'PUT');
      expect(captured.url.path, '/api/matches/m1/performances/p1/');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['minutesPlayed'], 80);
      expect(body.containsKey('club'), isFalse);
      expect(body.containsKey('playerId'), isFalse);
      expect(saved.coachRating, 8);
    },
  );

  test('guardian statistics read sends the player unlock token', () async {
    late http.Request captured;
    final api = AuthenticatedApiClient(
      identityProvider: () =>
          ApiIdentity(uid: 'guardian-1', getIdToken: (_) async => 'id-token'),
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'playerId': 'p1',
            'playerName': 'Ana Santos',
            'summary': <String, dynamic>{},
            'performances': <Map<String, dynamic>>[],
          }),
          200,
        );
      }),
    );
    final repository = ApiMatchRepository(
      api: api,
      unlockTokenFor: (playerId) => 'unlock-$playerId',
    );

    await repository.fetchPlayerStatistics('p1');

    expect(captured.method, 'GET');
    expect(captured.url.path, '/api/players/p1/match-statistics/');
    expect(captured.headers['X-Player-Unlock'], 'unlock-p1');
  });
}
