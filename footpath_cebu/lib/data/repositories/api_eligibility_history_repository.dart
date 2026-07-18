import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:footpath_cebu/core/config/api_config.dart';
import 'package:footpath_cebu/domain/entities/eligibility_change.dart';
import 'package:footpath_cebu/domain/repositories/eligibility_history_repository.dart';
import 'package:http/http.dart' as http;

/// Live implementation backed by the Django REST API, authenticated with the
/// signed-in user's Firebase ID token (same pattern as [ApiInjuryRepository]).
///
/// The server scopes access (player self / linked guardian / staff / admin)
/// and shapes `changedBy` for the viewer — this class just fetches and parses.
class ApiEligibilityHistoryRepository implements EligibilityHistoryRepository {
  @override
  Future<List<EligibilityChange>> fetchHistoryForPlayer(
    String playerId,
  ) async {
    final idToken = await _requireIdToken();

    final http.Response response;
    try {
      response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/players/$playerId/eligibility-history/',
        ),
        headers: {'Authorization': 'Bearer $idToken'},
      );
    } catch (_) {
      throw EligibilityHistoryRepositoryException(
        'Could not reach the server. Is it running?',
      );
    }

    if (response.statusCode != 200) {
      throw EligibilityHistoryRepositoryException(
        'Request failed (${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body);
    final list = decoded is Map<String, dynamic>
        ? (decoded['results'] as List? ?? const [])
        : (decoded as List? ?? const []);
    return list
        .cast<Map<String, dynamic>>()
        .map(EligibilityChange.fromJson)
        .toList();
  }

  Future<String> _requireIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw EligibilityHistoryRepositoryException('Not signed in.');
    }
    final token = await user.getIdToken();
    if (token == null) {
      throw EligibilityHistoryRepositoryException('Not signed in.');
    }
    return token;
  }
}
