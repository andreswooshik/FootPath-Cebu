import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:footpath_cebu/core/config/api_config.dart';
import 'package:footpath_cebu/domain/entities/session_confirmation.dart';
import 'package:footpath_cebu/domain/repositories/session_confirmation_repository.dart';
import 'package:http/http.dart' as http;

/// Live implementation backed by the Django REST API, authenticated with the
/// signed-in user's Firebase ID token (same pattern as [ApiAttendanceRepository]).
///
/// Confirmations now persist server-side, so a player's RSVPs survive logout,
/// app restarts, and are visible to the coach — unlike the in-memory mock.
class ApiSessionConfirmationRepository
    implements SessionConfirmationRepository {
  static const _path = '/api/session-confirmations/';

  @override
  Future<List<SessionConfirmation>> fetchConfirmationsForPlayer(
    String playerId,
  ) async {
    final idToken = await _requireIdToken();

    final http.Response response;
    try {
      response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}$_path?player=$playerId'),
        headers: {'Authorization': 'Bearer $idToken'},
      );
    } catch (_) {
      throw SessionConfirmationRepositoryException(
        'Could not reach the server. Is it running?',
      );
    }

    if (response.statusCode != 200) {
      throw SessionConfirmationRepositoryException(
        'Request failed (${response.statusCode}).',
      );
    }

    return _decode(response.body)
      ..sort((a, b) => b.respondedAt.compareTo(a.respondedAt));
  }

  @override
  Future<SessionConfirmation> confirmSession(
    String sessionId,
    String playerId,
    ConfirmationStatus status,
  ) async {
    final idToken = await _requireIdToken();

    // The player is derived from the authenticated request server-side, so
    // only the session and the intended status are sent.
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}$_path'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'sessionId': sessionId, 'status': status.wire}),
      );
    } catch (_) {
      throw SessionConfirmationRepositoryException(
        'Could not reach the server. Is it running?',
      );
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw SessionConfirmationRepositoryException(
        'Request failed (${response.statusCode}).',
      );
    }

    return SessionConfirmation.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
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

  Future<String> _requireIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw SessionConfirmationRepositoryException('Not signed in.');
    }
    final token = await user.getIdToken();
    if (token == null) {
      throw SessionConfirmationRepositoryException('Not signed in.');
    }
    return token;
  }
}
