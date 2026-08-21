import 'dart:convert';

import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/entities/eligibility_change.dart';
import 'package:footpath_cebu/domain/repositories/eligibility_history_repository.dart';

/// Live implementation backed by the Django REST API, authenticated with the
/// signed-in user's Firebase ID token (same pattern as [ApiInjuryRepository]).
///
/// The server scopes access (player self / linked guardian / staff / admin)
/// and shapes `changedBy` for the viewer — this class just fetches and parses.
class ApiEligibilityHistoryRepository implements EligibilityHistoryRepository {
  ApiEligibilityHistoryRepository({
    this.unlockTokenFor,
    AuthenticatedApiClient? api,
  }) : _api = api ?? AuthenticatedApiClient.shared;

  final String? Function(String playerId)? unlockTokenFor;
  final AuthenticatedApiClient _api;

  @override
  Future<List<EligibilityChange>> fetchHistoryForPlayer(
    String playerId, {
    String? unlockToken,
  }) async {
    final playerUnlock = unlockToken ?? unlockTokenFor?.call(playerId);
    try {
      final response = await _api.get(
        '/api/players/$playerId/eligibility-history/',
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
          .map(EligibilityChange.fromJson)
          .toList();
    } on ApiException catch (error) {
      throw EligibilityHistoryRepositoryException(error.message);
    }
  }
}
