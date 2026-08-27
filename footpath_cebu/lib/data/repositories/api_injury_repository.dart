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

  Map<String, String> _headersFor(
    String playerId, {
    bool json = false,
    String? unlockToken,
  }) {
    final playerUnlock = unlockToken ?? unlockTokenFor?.call(playerId);
    return {
      if (json) 'Content-Type': 'application/json',
      if (playerUnlock != null && playerUnlock.isNotEmpty)
        'X-Player-Unlock': playerUnlock,
    };
  }

  List<InjuryRecord> _decodeRecords(String body) {
    final decoded = jsonDecode(body);
    final list = decoded is Map<String, dynamic>
        ? (decoded['results'] as List? ?? const [])
        : (decoded as List? ?? const []);
    return list
        .cast<Map<String, dynamic>>()
        .map(InjuryRecord.fromJson)
        .toList();
  }

  @override
  Future<List<InjuryRecord>> fetchInjuriesForPlayer(
    String playerId, {
    String? unlockToken,
  }) async {
    try {
      final response = await _api.get(
        '$_path?player=$playerId',
        headers: _headersFor(playerId, unlockToken: unlockToken),
      );
      return _decodeRecords(response.body);
    } on ApiException catch (error) {
      throw InjuryRepositoryException(error.message);
    }
  }

  @override
  Future<List<InjuryRecord>> fetchClubInjuries({
    bool includeArchived = false,
  }) async {
    try {
      final response = await _api.get(
        '$_path${includeArchived ? '?includeArchived=true' : ''}',
      );
      return _decodeRecords(response.body);
    } on ApiException catch (error) {
      throw InjuryRepositoryException(error.message);
    }
  }

  @override
  Future<List<InjuryPlayerOption>> fetchReportablePlayers() async {
    try {
      final response = await _api.get('${_path}reportable-players/');
      return (jsonDecode(response.body) as List)
          .cast<Map<String, dynamic>>()
          .map(InjuryPlayerOption.fromJson)
          .toList(growable: false);
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
              headers: _headersFor(record.playerId, json: true),
              body: jsonEncode(record.toJson()),
              expectedStatuses: const {200, 201},
            )
          : await _api.put(
              '$_path$id/',
              headers: _headersFor(record.playerId, json: true),
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
  Future<void> deleteInjury(InjuryRecord record) async {
    try {
      await _api.delete(
        '$_path${record.id}/',
        headers: _headersFor(record.playerId),
      );
    } on ApiException catch (error) {
      throw InjuryRepositoryException(error.message);
    }
  }

  @override
  Future<InjuryRecord> reviewInjury(
    String injuryId, {
    required bool confirm,
    String rejectionReason = '',
  }) async {
    try {
      final response = await _api.post(
        '$_path$injuryId/review/',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': confirm ? 'CONFIRM' : 'REJECT',
          'rejectionReason': rejectionReason,
        }),
      );
      return InjuryRecord.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on ApiException catch (error) {
      throw InjuryRepositoryException(error.message);
    }
  }

  @override
  Future<InjuryRecord> archiveInjury(String injuryId) async {
    try {
      final response = await _api.post('$_path$injuryId/archive/');
      return InjuryRecord.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on ApiException catch (error) {
      throw InjuryRepositoryException(error.message);
    }
  }

  @override
  Future<InjuryStatusUpdate> requestStatusUpdate(
    InjuryRecord injury,
    InjuryStatusUpdateDraft draft,
  ) async {
    try {
      final response = await _api.post(
        '$_path${injury.id}/status-updates/',
        headers: _headersFor(injury.playerId, json: true),
        body: jsonEncode(draft.toJson()),
        expectedStatuses: const {201},
      );
      return InjuryStatusUpdate.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on ApiException catch (error) {
      throw InjuryRepositoryException(error.message);
    }
  }

  @override
  Future<InjuryRecord> reviewStatusUpdate(
    String injuryId,
    String updateId, {
    required bool approve,
    String rejectionReason = '',
  }) async {
    try {
      final response = await _api.post(
        '$_path$injuryId/status-updates/$updateId/review/',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': approve ? 'APPROVE' : 'REJECT',
          'rejectionReason': rejectionReason,
        }),
      );
      return InjuryRecord.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on ApiException catch (error) {
      throw InjuryRepositoryException(error.message);
    }
  }
}
