import 'dart:convert';

import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/repositories/age_tier_repository.dart';

/// Live implementation backed by GET /api/age-tiers/ (readable by every
/// signed-in role; writes are Admin-only server-side).
class ApiAgeTierRepository implements AgeTierRepository {
  ApiAgeTierRepository({AuthenticatedApiClient? api})
    : _api = api ?? AuthenticatedApiClient.shared;

  final AuthenticatedApiClient _api;

  @override
  Future<Map<AgeTier, AgeBand>> fetchBands() async {
    try {
      final response = await _api.get('/api/age-tiers/');
      final bands = <AgeTier, AgeBand>{};
      for (final row
          in (jsonDecode(response.body) as List).cast<Map<String, dynamic>>()) {
        final tier = AgeTierInfo.fromWire(row['tier'] as String? ?? '');
        bands[tier] = (
          min: row['minAge'] as int? ?? tier.ageRange.min,
          max: row['maxAge'] as int? ?? tier.ageRange.max,
        );
      }
      return bands;
    } on ApiException catch (error) {
      throw AgeTierRepositoryException(error.message);
    }
  }
}
