import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:footpath_cebu/core/config/api_config.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';
import 'package:http/http.dart' as http;

/// Live implementation backed by the Django REST API, authenticated with the
/// signed-in coach's Firebase ID token (same pattern as
/// [FirebaseAuthRepository]).
class ApiPlayerRepository implements PlayerRepository {
  @override
  Future<List<Player>> fetchSquad() => _getList('/api/players/');

  @override
  Future<List<Player>> fetchLinkedPlayers() =>
      _getList('/api/players/linked/');

  @override
  Future<Player> fetchMyProfile() async {
    final json = await _get('/api/players/me/');
    return Player.fromJson(json);
  }

  /// GETs a single JSON object from [path] with the coach/player's ID token.
  Future<Map<String, dynamic>> _get(String path) async {
    final idToken = await _requireIdToken();

    final http.Response response;
    try {
      response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}$path'),
        headers: {'Authorization': 'Bearer $idToken'},
      );
    } catch (_) {
      throw PlayerRepositoryException(
        'Could not reach the server. Is it running?',
      );
    }

    if (response.statusCode != 200) {
      throw PlayerRepositoryException(
        'Request failed (${response.statusCode}).',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// GETs a JSON list (or paginated `results`) from [path].
  Future<List<Player>> _getList(String path) async {
    final idToken = await _requireIdToken();

    final http.Response response;
    try {
      response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}$path'),
        headers: {'Authorization': 'Bearer $idToken'},
      );
    } catch (_) {
      throw PlayerRepositoryException(
        'Could not reach the server. Is it running?',
      );
    }

    if (response.statusCode != 200) {
      throw PlayerRepositoryException(
        'Request failed (${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body);
    final list = decoded is Map<String, dynamic>
        ? (decoded['results'] as List? ?? const [])
        : (decoded as List? ?? const []);

    return list
        .cast<Map<String, dynamic>>()
        .map(Player.fromJson)
        .toList(growable: false);
  }

  Future<String> _requireIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw PlayerRepositoryException('Not signed in.');
    }
    final token = await user.getIdToken();
    if (token == null) {
      throw PlayerRepositoryException('Not signed in.');
    }
    return token;
  }
}
