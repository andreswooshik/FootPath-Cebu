import 'dart:convert';

import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/entities/tournament_roster.dart';
import 'package:footpath_cebu/domain/repositories/tournament_roster_repository.dart';

class ApiTournamentRosterRepository implements TournamentRosterRepository {
  ApiTournamentRosterRepository({AuthenticatedApiClient? api})
    : _api = api ?? AuthenticatedApiClient.shared;

  final AuthenticatedApiClient _api;

  Future<TournamentSquad> _squad(Future<dynamic> Function() request) async {
    try {
      final response = await request();
      return TournamentSquad.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on ApiException catch (error) {
      throw TournamentRosterRepositoryException(
        error.message,
        statusCode: error is ApiHttpException ? error.statusCode : null,
      );
    }
  }

  @override
  Future<TournamentSquad> fetchSquad(String bracketId) =>
      _squad(() => _api.get('/api/tournament-brackets/$bracketId/squad/'));

  @override
  Future<List<TournamentRosterCandidate>> fetchCandidates(
    String bracketId,
  ) async {
    try {
      final response = await _api.get(
        '/api/tournament-brackets/$bracketId/squad/candidates/',
      );
      return (jsonDecode(response.body) as List)
          .cast<Map<String, dynamic>>()
          .map(TournamentRosterCandidate.fromJson)
          .toList(growable: false);
    } on ApiException catch (error) {
      throw TournamentRosterRepositoryException(
        error.message,
        statusCode: error is ApiHttpException ? error.statusCode : null,
      );
    }
  }

  @override
  Future<TournamentSquad> saveSquad(
    String bracketId,
    List<TournamentRosterSelection> entries,
  ) => _squad(
    () => _api.put(
      '/api/tournament-brackets/$bracketId/squad/',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'entries': entries.map((entry) => entry.toJson()).toList(),
      }),
    ),
  );

  @override
  Future<TournamentSquad> publishSquad(String bracketId) => _squad(
    () => _api.post('/api/tournament-brackets/$bracketId/squad/publish/'),
  );
}
