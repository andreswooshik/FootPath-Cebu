import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:footpath_cebu/core/config/api_config.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/domain/repositories/training_repository.dart';
import 'package:http/http.dart' as http;

/// Live implementation backed by the Django REST API, authenticated with the
/// signed-in coach's Firebase ID token (same pattern as [ApiPlayerRepository]).
class ApiTrainingRepository implements TrainingRepository {
  static const _path = '/api/training-sessions/';

  @override
  Future<List<TrainingSession>> fetchSessions() async {
    final idToken = await _requireIdToken();

    final http.Response response;
    try {
      response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}$_path'),
        headers: {'Authorization': 'Bearer $idToken'},
      );
    } catch (_) {
      throw TrainingRepositoryException(
        'Could not reach the server. Is it running?',
      );
    }

    if (response.statusCode != 200) {
      throw TrainingRepositoryException(
        'Request failed (${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body);
    final list = decoded is Map<String, dynamic>
        ? (decoded['results'] as List? ?? const [])
        : (decoded as List? ?? const []);

    return list
        .cast<Map<String, dynamic>>()
        .map(TrainingSession.fromJson)
        .toList(growable: false);
  }

  @override
  Future<TrainingSession> createSession(TrainingSession draft) async {
    final idToken = await _requireIdToken();

    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}$_path'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(draft.toJson()),
      );
    } catch (_) {
      throw TrainingRepositoryException(
        'Could not reach the server. Is it running?',
      );
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw TrainingRepositoryException(
        'Could not schedule the session (${response.statusCode}).',
      );
    }
    return TrainingSession.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  @override
  Future<TrainingSession> updateSession(TrainingSession session) async {
    final idToken = await _requireIdToken();

    final http.Response response;
    try {
      response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}$_path${session.id}/'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(session.toJson()),
      );
    } catch (_) {
      throw TrainingRepositoryException(
        'Could not reach the server. Is it running?',
      );
    }

    if (response.statusCode != 200) {
      throw TrainingRepositoryException(
        'Could not save the session (${response.statusCode}).',
      );
    }
    return TrainingSession.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> deleteSession(String id) async {
    final idToken = await _requireIdToken();

    final http.Response response;
    try {
      response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}$_path$id/'),
        headers: {'Authorization': 'Bearer $idToken'},
      );
    } catch (_) {
      throw TrainingRepositoryException(
        'Could not reach the server. Is it running?',
      );
    }

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw TrainingRepositoryException(
        'Could not cancel the session (${response.statusCode}).',
      );
    }
  }

  Future<String> _requireIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw TrainingRepositoryException('Not signed in.');
    }
    final token = await user.getIdToken();
    if (token == null) {
      throw TrainingRepositoryException('Not signed in.');
    }
    return token;
  }
}
