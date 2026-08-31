import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/data/repositories/api_growth_repository.dart';
import 'package:footpath_cebu/domain/entities/player_growth.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('sends shared growth filters and the guardian unlock token', () async {
    late http.Request captured;
    final api = AuthenticatedApiClient(
      identityProvider: () =>
          ApiIdentity(uid: 'guardian-1', getIdToken: (_) async => 'id-token'),
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'playerId': '12',
            'playerName': 'Alex Santos',
            'position': 'GK',
            'assessments': null,
            'training': {'groups': []},
            'regularMatches': null,
            'tournaments': null,
          }),
          200,
        );
      }),
    );
    final repository = ApiGrowthRepository(
      api: api,
      unlockTokenFor: (_) => 'unlock-token',
    );

    final result = await repository.fetchGrowth(
      GrowthQuery(
        playerId: '12',
        range: GrowthRange.last90Days,
        category: GrowthCategory.training,
        from: DateTime(2026, 6, 1),
        to: DateTime(2026, 8, 29),
      ),
    );

    expect(captured.url.path, '/api/players/12/growth/');
    expect(captured.url.queryParameters, {
      'range': 'last90days',
      'category': 'training',
      'from': '2026-06-01',
      'to': '2026-08-29',
    });
    expect(captured.headers['x-player-unlock'], 'unlock-token');
    expect(result.position, 'GK');
    expect(result.training, isEmpty);
  });
}
