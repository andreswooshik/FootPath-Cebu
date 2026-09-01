import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/player_stats.dart';

final playerStatsProvider = FutureProvider.autoDispose
    .family<PlayerStats, String>(
      (ref, playerId) =>
          ref.watch(playerStatsRepositoryProvider).fetchStats(playerId),
    );
