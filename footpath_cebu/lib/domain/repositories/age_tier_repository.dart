import 'package:footpath_cebu/domain/entities/age_tier.dart';

/// One tier's Admin-configured age band.
typedef AgeBand = ({int min, int max});

/// Reads the Admin-configured age band per tier from the backend.
///
/// The tier *set* is fixed (a wire contract, see [AgeTier]); only the
/// boundaries are configurable. UI that prints a band should prefer these
/// over the hardcoded [AgeTierInfo.ageRange] fallback, so a retuned band
/// shows up in the app without a release.
abstract class AgeTierRepository {
  Future<Map<AgeTier, AgeBand>> fetchBands();
}

/// Thrown when the tier bands cannot be loaded.
class AgeTierRepositoryException implements Exception {
  AgeTierRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}
