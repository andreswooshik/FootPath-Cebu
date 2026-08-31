import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/player_growth.dart';

final playerGrowthProvider = FutureProvider.autoDispose
    .family<PlayerGrowth, GrowthQuery>(
      (ref, query) => ref.watch(growthRepositoryProvider).fetchGrowth(query),
    );
