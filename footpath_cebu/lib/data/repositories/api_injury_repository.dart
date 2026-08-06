import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:footpath_cebu/core/config/api_config.dart';
import 'package:footpath_cebu/domain/entities/injury_record.dart';
import 'package:footpath_cebu/domain/repositories/injury_repository.dart';
import 'package:http/http.dart' as http;

/// Live implementation backed by the Django REST API, authenticated with the
/// signed-in user's Firebase ID token (same pattern as
/// [ApiAttendanceRepository]).
class ApiInjuryRepository implements InjuryRepository {
  ApiInjuryRepository({this.unlockTokenFor});

  final String? Function(String playerId)? unlockTokenFor;

  static const _path = '/api/injuries/';

  @override
  Future<List<InjuryRecord>> fetchInjuriesForPlayer(
    String playerId, {
    String? unlockToken,
  }) async {
    final playerUnlock = unlockToken ?? unlockTokenFor?.call(playerId);
    final response = await _send(
      (token) => http.get(
        // The server scopes a player to their own records regardless; the
        // query narrows the coach/admin read to one player.
        Uri.parse('${ApiConfig.baseUrl}$_path?player=$playerId'),
        headers: {
          'Authorization': 'Bearer $token',
          if (playerUnlock != null && playerUnlock.isNotEmpty)
            'X-Player-Unlock': playerUnlock,
        },
      ),
    );
    if (response.statusCode != 200) {
      throw InjuryRepositoryException(
        'Request failed (${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body);
    final list = decoded is Map<String, dynamic>
        ? (decoded['results'] as List? ?? const [])
        : (decoded as List? ?? const []);
    return list
        .cast<Map<String, dynamic>>()
        .map(InjuryRecord.fromJson)
        .toList();
  }

  @override
  Future<InjuryRecord> saveInjury(InjuryRecord record) async {
    final id = record.id;
    final response = await _send((token) {
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      final body = jsonEncode(record.toJson());
      return id == null
          ? http.post(
              Uri.parse('${ApiConfig.baseUrl}$_path'),
              headers: headers,
              body: body,
            )
          : http.put(
              Uri.parse('${ApiConfig.baseUrl}$_path$id/'),
              headers: headers,
              body: body,
            );
    });
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw InjuryRepositoryException(
        'Could not save the injury (${response.statusCode}).',
      );
    }
    return InjuryRecord.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> deleteInjury(String injuryId) async {
    final response = await _send(
      (token) => http.delete(
        Uri.parse('${ApiConfig.baseUrl}$_path$injuryId/'),
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
    if (response.statusCode != 204) {
      throw InjuryRepositoryException(
        'Could not delete the injury (${response.statusCode}).',
      );
    }
  }

  /// Runs one authenticated request, translating connection-level failures
  /// into [InjuryRepositoryException].
  Future<http.Response> _send(
    Future<http.Response> Function(String idToken) request,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw InjuryRepositoryException('Not signed in.');
    }
    final token = await user.getIdToken();
    if (token == null) {
      throw InjuryRepositoryException('Not signed in.');
    }
    try {
      return await request(token);
    } catch (_) {
      throw InjuryRepositoryException(
        'Could not reach the server. Is it running?',
      );
    }
  }
}
