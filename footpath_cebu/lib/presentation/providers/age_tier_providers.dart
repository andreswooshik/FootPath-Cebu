import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/repositories/age_tier_repository.dart';

/// The Admin-configured age band per tier, fetched once per session and
/// cached (not autoDispose — the bands change rarely and every tier chip
/// reads them).
final ageTierBandsProvider = FutureProvider<Map<AgeTier, AgeBand>>(
  (ref) => ref.watch(getAgeTierBandsProvider)(),
);

/// "Ages 10–12" for [tier], preferring the server-configured band and
/// falling back to the compiled-in range while loading or offline.
String tierAgeLabel(AgeTier tier, Map<AgeTier, AgeBand>? bands) {
  final band = bands?[tier];
  if (band == null) return tier.ageLabel;
  return 'Ages ${band.min}–${band.max}';
}
