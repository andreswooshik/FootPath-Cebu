import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/repositories/age_tier_repository.dart';

/// The canonical bands, served from memory for UI development.
class MockAgeTierRepository implements AgeTierRepository {
  @override
  Future<Map<AgeTier, AgeBand>> fetchBands() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return {
      for (final tier in AgeTier.values)
        tier: (min: tier.ageRange.min, max: tier.ageRange.max),
    };
  }
}
