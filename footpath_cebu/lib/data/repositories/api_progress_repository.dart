import 'dart:convert';

import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/entities/player_progress.dart';
import 'package:footpath_cebu/domain/repositories/progress_repository.dart';

/// Live implementation backed by GET /api/progress/squad/ — one aggregate
/// call, not one request per player (same auth pattern as the other Api
/// repositories).
class ApiProgressRepository implements ProgressRepository {
  ApiProgressRepository({AuthenticatedApiClient? api})
    : _api = api ?? AuthenticatedApiClient.shared;

  final AuthenticatedApiClient _api;

  @override
  Future<List<PlayerProgress>> fetchSquadProgress() async {
    try {
      final response = await _api.get('/api/progress/squad/');
      return (jsonDecode(response.body) as List)
          .cast<Map<String, dynamic>>()
          .map(PlayerProgress.fromJson)
          .toList(growable: false);
    } on ApiException catch (error) {
      throw ProgressRepositoryException(error.message);
    }
  }
}
