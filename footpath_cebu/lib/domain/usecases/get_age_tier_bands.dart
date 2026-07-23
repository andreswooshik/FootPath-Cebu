import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/repositories/age_tier_repository.dart';

/// Use case: load the Admin-configured age band per tier.
class GetAgeTierBands {
  const GetAgeTierBands(this._repository);

  final AgeTierRepository _repository;

  Future<Map<AgeTier, AgeBand>> call() => _repository.fetchBands();
}
