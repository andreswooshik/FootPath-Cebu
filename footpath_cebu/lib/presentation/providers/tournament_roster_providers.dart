import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/presentation/providers/mutation_controller.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/tournament_roster.dart';
import 'package:footpath_cebu/presentation/providers/tournament_schedule_providers.dart';

final tournamentRosterCandidatesProvider = FutureProvider.autoDispose
    .family<List<TournamentRosterCandidate>, String>(
      (ref, bracketId) => ref
          .watch(tournamentRosterRepositoryProvider)
          .fetchCandidates(bracketId),
    );

class TournamentRosterManagementController extends MutationController {
  /// Saves the selected players for a tournament age bracket.
  Future<TournamentSquad?> save(
    String bracketId,
    List<TournamentRosterSelection> entries,
  ) => _run(
    bracketId,
    () => ref
        .read(tournamentRosterRepositoryProvider)
        .saveSquad(bracketId, entries),
  );

  /// Publishes the saved squad for the tournament age bracket.
  Future<TournamentSquad?> publish(String bracketId) => _run(
    bracketId,
    () => ref.read(tournamentRosterRepositoryProvider).publishSquad(bracketId),
  );

  /// Fetches the latest squad and refreshes schedule and candidate data.
  Future<TournamentSquad?> refresh(String bracketId) => _run(
    bracketId,
    () => ref.read(tournamentRosterRepositoryProvider).fetchSquad(bracketId),
  );

  /// Runs a squad action and refreshes the tournament schedule and bracket
  /// candidates.
  Future<TournamentSquad?> _run(
    String bracketId,
    Future<TournamentSquad> Function() action,
  ) async {
    return runMutation(
      () async {
        final result = await action();
        return result;
      },
      onSuccess: (result) {
        ref.invalidate(tournamentSchedulesProvider);
        ref.invalidate(tournamentRosterCandidatesProvider(bracketId));
      },
    );
  }
}

final tournamentRosterManagementControllerProvider =
    AsyncNotifierProvider.autoDispose<
      TournamentRosterManagementController,
      void
    >(TournamentRosterManagementController.new);
