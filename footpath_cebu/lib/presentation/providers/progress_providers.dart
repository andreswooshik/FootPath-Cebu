import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/player_progress.dart';

/// The squad's per-player attendance/effort aggregates for the coach's
/// Progress tab. Refresh with `ref.refresh(squadProgressProvider.future)`.
final squadProgressProvider =
    FutureProvider.autoDispose<List<PlayerProgress>>(
  (ref) => ref.watch(getSquadProgressProvider)(),
);
