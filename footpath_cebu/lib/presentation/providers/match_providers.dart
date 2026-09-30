import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/presentation/providers/mutation_controller.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/match_performance.dart';

final footballMatchesProvider = FutureProvider.autoDispose<List<FootballMatch>>(
  (ref) => ref.watch(getFootballMatchesProvider)(),
);

final matchPerformancesProvider = FutureProvider.autoDispose
    .family<List<MatchPerformance>, String>(
      (ref, matchId) => ref.watch(getMatchPerformancesProvider)(matchId),
    );

final matchRosterProvider = FutureProvider.autoDispose
    .family<List<MatchRosterPlayer>, String>(
      (ref, matchId) => ref.watch(getMatchRosterProvider)(matchId),
    );

final outOfSquadMatchCandidatesProvider = FutureProvider.autoDispose
    .family<List<MatchRosterPlayer>, String>((ref, matchId) async {
      final rows = await ref.watch(getMatchRosterProvider)(
        matchId,
        includeOutOfSquad: true,
      );
      return rows
          .where(
            (row) =>
                row.requiresSquadOverride &&
                row.performance == null &&
                row.isSelectable,
          )
          .toList(growable: false);
    });

final playerMatchStatisticsProvider = FutureProvider.autoDispose
    .family<PlayerMatchStatistics, String>(
      (ref, playerId) => ref.watch(getPlayerMatchStatisticsProvider)(playerId),
    );

/// Coordinates role-owned writes and refreshes every affected read model.
class MatchManagementController extends MutationController {
  /// Creates a match and refreshes the match list after a successful save.
  Future<FootballMatch?> create(FootballMatchDraft draft) async {
    return _run(
      () => ref.read(createFootballMatchProvider)(draft),
      onSuccess: (_) => ref.invalidate(footballMatchesProvider),
    );
  }

  /// Updates match details and refreshes the match list and its performances.
  Future<FootballMatch?> saveMatchChanges(
    String matchId,
    FootballMatchDraft draft,
  ) async {
    return _run(
      () => ref.read(updateFootballMatchProvider)(matchId, draft),
      onSuccess: (_) {
        ref.invalidate(footballMatchesProvider);
        ref.invalidate(matchPerformancesProvider(matchId));
      },
    );
  }

  /// Saves player match statistics and refreshes roster and player statistics
  /// views.
  Future<MatchPerformance?> savePerformance(
    String matchId,
    String playerId,
    MatchPerformanceDraft draft,
  ) async {
    return _run(
      () => ref.read(saveMatchPerformanceProvider)(matchId, playerId, draft),
      onSuccess: (_) {
        ref.invalidate(matchPerformancesProvider(matchId));
        ref.invalidate(matchRosterProvider(matchId));
        ref.invalidate(outOfSquadMatchCandidatesProvider(matchId));
        ref.invalidate(playerMatchStatisticsProvider(playerId));
      },
    );
  }

  /// Deletes player match statistics and refreshes affected roster and
  /// statistics views.
  Future<bool> deletePerformance(String matchId, String playerId) async {
    return await runMutation(
          () async {
            await ref.read(deleteMatchPerformanceProvider)(matchId, playerId);
            return true;
          },
          onSuccess: (result) {
            ref.invalidate(matchPerformancesProvider(matchId));
            ref.invalidate(matchRosterProvider(matchId));
            ref.invalidate(outOfSquadMatchCandidatesProvider(matchId));
            ref.invalidate(playerMatchStatisticsProvider(playerId));
          },
        ) ??
        false;
  }

  /// Saves a player match rating and refreshes affected roster and statistics
  /// views.
  Future<MatchPerformance?> saveRating(
    String matchId,
    String playerId,
    MatchRatingDraft draft,
  ) async {
    return _run(
      () => ref.read(saveMatchRatingProvider)(matchId, playerId, draft),
      onSuccess: (_) {
        ref.invalidate(matchPerformancesProvider(matchId));
        ref.invalidate(matchRosterProvider(matchId));
        ref.invalidate(outOfSquadMatchCandidatesProvider(matchId));
        ref.invalidate(playerMatchStatisticsProvider(playerId));
      },
    );
  }

  /// Deletes a player match rating and refreshes affected roster and statistics
  /// views.
  Future<bool> deleteRating(String matchId, String playerId) async {
    return await runMutation(
          () async {
            await ref.read(deleteMatchRatingProvider)(matchId, playerId);
            return true;
          },
          onSuccess: (result) {
            ref.invalidate(matchPerformancesProvider(matchId));
            ref.invalidate(matchRosterProvider(matchId));
            ref.invalidate(outOfSquadMatchCandidatesProvider(matchId));
            ref.invalidate(playerMatchStatisticsProvider(playerId));
          },
        ) ??
        false;
  }

  /// Runs a match mutation and invokes its refresh callback after a successful
  /// write.
  Future<T?> _run<T>(
    Future<T> Function() action, {
    required void Function(T value) onSuccess,
  }) async {
    return runMutation(
      () async {
        final value = await action();
        return value;
      },
      onSuccess: (result) {
        onSuccess(result);
      },
    );
  }
}

final matchManagementControllerProvider =
    AsyncNotifierProvider.autoDispose<MatchManagementController, void>(
      MatchManagementController.new,
    );
