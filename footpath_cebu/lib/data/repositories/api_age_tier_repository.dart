import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:footpath_cebu/core/config/api_config.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/repositories/age_tier_repository.dart';
import 'package:http/http.dart' as http;

/// Live implementation backed by GET /api/age-tiers/ (readable by every
/// signed-in role; writes are Admin-only server-side).
class ApiAgeTierRepository implements AgeTierRepository {
  @override
  Future<Map<AgeTier, AgeBand>> fetchBands() async {
    final user = FirebaseAuth.instance.currentUser;
    final idToken = await user?.getIdToken();
    if (idToken == null) {
      throw AgeTierRepositoryException('Not signed in.');
    }

    final http.Response response;
    try {
      response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/age-tiers/'),
        headers: {'Authorization': 'Bearer $idToken'},
      );
    } catch (_) {
      throw AgeTierRepositoryException(
        'Could not reach the server. Is it running?',
      );
    }

    if (response.statusCode != 200) {
      throw AgeTierRepositoryException(
        'Request failed (${response.statusCode}).',
      );
    }

    final bands = <AgeTier, AgeBand>{};
    for (final row in (jsonDecode(response.body) as List)
        .cast<Map<String, dynamic>>()) {
      final tier = AgeTierInfo.fromWire(row['tier'] as String? ?? '');
      bands[tier] = (
        min: row['minAge'] as int? ?? tier.ageRange.min,
        max: row['maxAge'] as int? ?? tier.ageRange.max,
      );
    }
    return bands;
  }
}
