import 'dart:convert';

import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/entities/injury_record.dart';
import 'package:footpath_cebu/domain/repositories/injury_repository.dart';

/// Live injury data backed by the authenticated Django REST API.
class ApiInjuryRepository implements InjuryRepository {
  ApiInjuryRepository({this.unlockTokenFor, AuthenticatedApiClient? api})
    : _api = api ?? AuthenticatedApiClient.shared;

  final String? Function(String playerId)? unlockTokenFor;
  final AuthenticatedApiClient _api;

  static const _path = '/api/injuries/';

  @override
  Future<List<InjuryRecord>> fetchInjuriesForPlayer(
    String playerId, {
    String? unlockToken,
  }) async {
    final playerUnlock = unlockToken ?? unlockTokenFor?.call(playerId);
    try {
      final response = await _api.get(
        '$_path?player=$playerId',
        headers: {
          if (playerUnlock != null && playerUnlock.isNotEmpty)
            'X-Player-Unlock': playerUnlock,
        },
      );
      final decoded = jsonDecode(response.body);
      final list = decoded is Map<String, dynamic>
          ? (decoded['results'] as List? ?? const [])
          : (decoded as List? ?? const []);
      return list
          .cast<Map<String, dynamic>>()
          .map(InjuryRecord.fromJson)
          .toList();
    } on ApiException catch (error) {
      throw InjuryRepositoryException(error.message);
    }
  }

  @override
  Future<InjuryRecord> saveInjury(InjuryRecord record) async {
    try {
      final id = record.id;
      final response = id == null
          ? await _api.post(
              _path,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(record.toJson()),
              expectedStatuses: const {200, 201},
            )
          : await _api.put(
              '$_path$id/',
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(record.toJson()),
              expectedStatuses: const {200, 201},
            );
      return InjuryRecord.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on ApiException catch (error) {
      throw InjuryRepositoryException(error.message);
    }
  }

  @override
  Future<void> deleteInjury(String injuryId) async {
    try {
      await _api.delete('$_path$injuryId/');
    } on ApiException catch (error) {
      throw InjuryRepositoryException(error.message);
    }
  }
}
