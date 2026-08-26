import 'dart:convert';

import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/match_performance.dart';
import 'package:footpath_cebu/domain/repositories/match_repository.dart';

class ApiMatchRepository implements MatchRepository {
  ApiMatchRepository({this.unlockTokenFor, AuthenticatedApiClient? api})
    : _api = api ?? AuthenticatedApiClient.shared;

  final String? Function(String playerId)? unlockTokenFor;
  final AuthenticatedApiClient _api;

  @override
  Future<List<FootballMatch>> fetchMatches() async {
    try {
      final response = await _api.get('/api/matches/');
      return (jsonDecode(response.body) as List)
          .cast<Map<String, dynamic>>()
          .map(FootballMatch.fromJson)
          .toList(growable: false);
    } on ApiException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<FootballMatch> createMatch(FootballMatchDraft draft) async {
    try {
      final response = await _api.post(
        '/api/matches/',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(draft.toJson()),
        expectedStatuses: const {201},
      );
      return FootballMatch.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on ApiException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<FootballMatch> updateMatch(
    String matchId,
    FootballMatchDraft draft,
  ) async {
    try {
      final response = await _api.put(
        '/api/matches/$matchId/',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(draft.toJson()),
      );
      return FootballMatch.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on ApiException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<List<MatchPerformance>> fetchMatchPerformances(String matchId) async {
    try {
      final response = await _api.get('/api/matches/$matchId/performances/');
      return (jsonDecode(response.body) as List)
          .cast<Map<String, dynamic>>()
          .map(MatchPerformance.fromJson)
          .toList(growable: false);
    } on ApiException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<MatchPerformance> savePerformance(
    String matchId,
    String playerId,
    MatchPerformanceDraft draft,
  ) async {
    try {
      final response = await _api.put(
        '/api/matches/$matchId/performances/$playerId/',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(draft.toJson()),
        expectedStatuses: const {200, 201},
      );
      return MatchPerformance.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on ApiException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<void> deletePerformance(String matchId, String playerId) async {
    try {
      await _api.delete('/api/matches/$matchId/performances/$playerId/');
    } on ApiException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<PlayerMatchStatistics> fetchPlayerStatistics(String playerId) async {
    final unlockToken = unlockTokenFor?.call(playerId);
    try {
      final response = await _api.get(
        '/api/players/$playerId/match-statistics/',
        headers: {
          if (unlockToken != null && unlockToken.isNotEmpty)
            'X-Player-Unlock': unlockToken,
        },
      );
      return PlayerMatchStatistics.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on ApiException catch (error) {
      throw _translate(error);
    }
  }

  MatchRepositoryException _translate(ApiException error) =>
      MatchRepositoryException(
        error.message,
        statusCode: error is ApiHttpException ? error.statusCode : null,
      );
}
