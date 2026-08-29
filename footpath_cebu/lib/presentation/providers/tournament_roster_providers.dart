import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/tournament_roster.dart';
import 'package:footpath_cebu/presentation/providers/tournament_schedule_providers.dart';

final tournamentRosterCandidatesProvider = FutureProvider.autoDispose
    .family<List<TournamentRosterCandidate>, String>(
      (ref, bracketId) => ref
          .watch(tournamentRosterRepositoryProvider)
          .fetchCandidates(bracketId),
    );

class TournamentRosterManagementController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<TournamentSquad?> save(
    String bracketId,
    List<TournamentRosterSelection> entries,
  ) => _run(
    bracketId,
    () => ref
        .read(tournamentRosterRepositoryProvider)
        .saveSquad(bracketId, entries),
  );

  Future<TournamentSquad?> publish(String bracketId) => _run(
    bracketId,
    () => ref.read(tournamentRosterRepositoryProvider).publishSquad(bracketId),
  );

  Future<TournamentSquad?> _run(
    String bracketId,
    Future<TournamentSquad> Function() action,
  ) async {
    state = const AsyncLoading();
    try {
      final result = await action();
      state = const AsyncData(null);
      ref.invalidate(tournamentSchedulesProvider);
      ref.invalidate(tournamentRosterCandidatesProvider(bracketId));
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return null;
    }
  }
}

final tournamentRosterManagementControllerProvider =
    AsyncNotifierProvider.autoDispose<
      TournamentRosterManagementController,
      void
    >(TournamentRosterManagementController.new);
