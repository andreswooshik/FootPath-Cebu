import 'dart:convert';

import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/domain/repositories/training_repository.dart';

/// Live implementation backed by the authenticated Django REST API.
class ApiTrainingRepository implements TrainingRepository {
  ApiTrainingRepository({AuthenticatedApiClient? api})
    : _api = api ?? AuthenticatedApiClient.shared;

  static const _path = '/api/training-sessions/';

  final AuthenticatedApiClient _api;

  @override
  Future<List<TrainingSession>> fetchSessions() async {
    try {
      final response = await _api.get(_path);
      final decoded = jsonDecode(response.body);
      final list = decoded is Map<String, dynamic>
          ? (decoded['results'] as List? ?? const [])
          : (decoded as List? ?? const []);
      return list
          .cast<Map<String, dynamic>>()
          .map(TrainingSession.fromJson)
          .toList(growable: false);
    } on ApiException catch (error) {
      throw TrainingRepositoryException(error.message);
    }
  }

  @override
  Future<TrainingSession> createSession(TrainingSession draft) async {
    try {
      final response = await _api.post(
        _path,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(draft.toJson()),
        expectedStatuses: const {200, 201},
      );
      return TrainingSession.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on ApiException catch (error) {
      throw TrainingRepositoryException(error.message);
    }
  }

  @override
  Future<TrainingSession> updateSession(TrainingSession session) async {
    try {
      final response = await _api.put(
        '$_path${session.id}/',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(session.toJson()),
      );
      return TrainingSession.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on ApiException catch (error) {
      throw TrainingRepositoryException(error.message);
    }
  }

  @override
  Future<void> deleteSession(String id) async {
    try {
      await _api.delete('$_path$id/', expectedStatuses: const {200, 204});
    } on ApiException catch (error) {
      throw TrainingRepositoryException(error.message);
    }
  }
}
