import 'package:footpath_cebu/presentation/providers/mutation_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/player_stats.dart';

final playerStatsProvider = FutureProvider.autoDispose
    .family<PlayerStats, String>(
      (ref, playerId) =>
          ref.watch(playerStatsRepositoryProvider).fetchStats(playerId),
    );

class PlayerStatsController extends MutationController {
  Future<PlayerStatsSaveResult?> save(
    String playerId,
    PlayerStatsDraft draft,
  ) => runMutation(
    () =>
        ref.read(playerStatsRepositoryProvider).saveAssessment(playerId, draft),
    onSuccess: (_) => ref.invalidate(playerStatsProvider(playerId)),
  );
}

final playerStatsControllerProvider = AsyncNotifierProvider.autoDispose
    .family<PlayerStatsController, void, String>(
      (_) => PlayerStatsController(),
    );
