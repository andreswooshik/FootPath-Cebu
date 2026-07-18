import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/eligibility_change.dart';

/// One player's eligibility transitions, newest first. Family-keyed by player
/// id so the player's own view and the guardian's per-child view share
/// caching — same shape as [injuriesProvider].
final eligibilityHistoryProvider =
    FutureProvider.autoDispose.family<List<EligibilityChange>, String>(
  (ref, playerId) => ref.watch(getEligibilityHistoryProvider)(playerId),
);
