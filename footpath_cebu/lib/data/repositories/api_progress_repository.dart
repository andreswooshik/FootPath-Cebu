import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:footpath_cebu/core/config/api_config.dart';
import 'package:footpath_cebu/domain/entities/player_progress.dart';
import 'package:footpath_cebu/domain/repositories/progress_repository.dart';
import 'package:http/http.dart' as http;

/// Live implementation backed by GET /api/progress/squad/ — one aggregate
/// call, not one request per player (same auth pattern as the other Api
/// repositories).
class ApiProgressRepository implements ProgressRepository {
  @override
  Future<List<PlayerProgress>> fetchSquadProgress() async {
    final user = FirebaseAuth.instance.currentUser;
    final idToken = await user?.getIdToken();
    if (idToken == null) {
      throw ProgressRepositoryException('Not signed in.');
    }

    final http.Response response;
    try {
      response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/progress/squad/'),
        headers: {'Authorization': 'Bearer $idToken'},
      );
    } catch (_) {
      throw ProgressRepositoryException(
        'Could not reach the server. Is it running?',
      );
    }

    if (response.statusCode != 200) {
      throw ProgressRepositoryException(
        'Request failed (${response.statusCode}).',
      );
    }

    return (jsonDecode(response.body) as List)
        .cast<Map<String, dynamic>>()
        .map(PlayerProgress.fromJson)
        .toList(growable: false);
  }
}
