import 'dart:convert';

import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/entities/session_confirmation.dart';
import 'package:footpath_cebu/domain/repositories/session_confirmation_repository.dart';

/// Live implementation backed by the Django REST API, authenticated with the
/// signed-in user's Firebase ID token (same pattern as [ApiAttendanceRepository]).
///
/// Confirmations now persist server-side, so a player's RSVPs survive logout,
/// app restarts, and are visible to the coach — unlike the in-memory mock.
class ApiSessionConfirmationRepository
    implements SessionConfirmationRepository {
  ApiSessionConfirmationRepository({AuthenticatedApiClient? api})
    : _api = api ?? AuthenticatedApiClient.shared;

  static const _path = '/api/session-confirmations/';

  final AuthenticatedApiClient _api;

  @override
  Future<List<SessionConfirmation>> fetchConfirmationsForPlayer(
    String playerId,
  ) async {
    try {
      final response = await _api.get('$_path?player=$playerId');
      return _decode(response.body)
        ..sort((a, b) => b.respondedAt.compareTo(a.respondedAt));
    } on ApiException catch (error) {
      throw SessionConfirmationRepositoryException(error.message);
    }
  }

  @override
  Future<SessionConfirmation> confirmSession(
    String sessionId,
    String playerId,
    ConfirmationStatus status,
  ) async {
    // The player is derived from the authenticated request server-side, so
    // only the session and the intended status are sent.
    try {
      final response = await _api.post(
        _path,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'sessionId': sessionId, 'status': status.wire}),
        expectedStatuses: const {200, 201},
      );
      return SessionConfirmation.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on ApiException catch (error) {
      throw SessionConfirmationRepositoryException(error.message);
    }
  }

  List<SessionConfirmation> _decode(String body) {
    final decoded = jsonDecode(body);
    final list = decoded is Map<String, dynamic>
        ? (decoded['results'] as List? ?? const [])
        : (decoded as List? ?? const []);
    return list
        .cast<Map<String, dynamic>>()
        .map(SessionConfirmation.fromJson)
        .toList();
  }
}
