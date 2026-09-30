import 'package:footpath_cebu/data/dto/player_stats_dto.dart';
import 'dart:convert';

import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/entities/player_stats.dart';
import 'package:footpath_cebu/domain/repositories/player_stats_repository.dart';

class ApiPlayerStatsRepository implements PlayerStatsRepository {
  ApiPlayerStatsRepository({AuthenticatedApiClient? api})
    : _api = api ?? AuthenticatedApiClient.shared;
  final AuthenticatedApiClient _api;

  @override
  Future<PlayerStats> fetchStats(
    String playerId, {
    bool forceRefresh = false,
  }) async {
    try {
      final response = await _api.get('/api/players/$playerId/stats/');
      return PlayerStatsDto.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on ApiException catch (error) {
      throw PlayerStatsRepositoryException(error.message);
    }
  }

  @override
  Future<PlayerStatsSaveResult> saveAssessment(
    String playerId,
    PlayerStatsDraft draft,
  ) async {
    try {
      final response = await _api.post(
        '/api/players/$playerId/stats/',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(draft.toJson()),
        expectedStatuses: const {201},
      );
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return PlayerStatsSaveResult(
        assessment: PlayerStatsAssessmentDto.fromJson(
          json['assessment'] as Map<String, dynamic>,
        ),
        comparison: PlayerStatsComparisonDto.fromJson(
          json['comparison'] as Map<String, dynamic>,
        ),
      );
    } on ApiException catch (error) {
      throw PlayerStatsRepositoryException(error.message);
    }
  }
}
