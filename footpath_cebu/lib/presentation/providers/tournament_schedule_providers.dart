import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';

final tournamentSchedulesProvider =
    FutureProvider.autoDispose<List<TournamentSchedule>>((ref) {
      return ref.watch(tournamentScheduleRepositoryProvider).fetchSchedules();
    });

class TournamentManagementController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<TournamentSchedule?> create({
    required String title,
    required DateTime startsOn,
  }) => _run(
    () => ref
        .read(tournamentScheduleRepositoryProvider)
        .createTournament(title: title, startsOn: startsOn),
  );

  Future<TournamentSchedule?> saveTournament(TournamentSchedule tournament) =>
      _run(
        () => ref
            .read(tournamentScheduleRepositoryProvider)
            .updateTournament(tournament),
      );

  Future<TournamentSchedule?> addBracket(
    String tournamentId, {
    required int maxAge,
    DateTime? scheduledAt,
  }) => _run(
    () => ref
        .read(tournamentScheduleRepositoryProvider)
        .addAgeBracket(tournamentId, maxAge: maxAge, scheduledAt: scheduledAt),
  );

  Future<TournamentSchedule?> updateBracket(
    String bracketId, {
    required int maxAge,
    DateTime? scheduledAt,
  }) => _run(
    () => ref
        .read(tournamentScheduleRepositoryProvider)
        .updateAgeBracket(bracketId, maxAge: maxAge, scheduledAt: scheduledAt),
  );

  Future<bool> deleteBracket(String bracketId) async {
    state = const AsyncLoading();
    try {
      await ref
          .read(tournamentScheduleRepositoryProvider)
          .deleteAgeBracket(bracketId);
      state = const AsyncData(null);
      ref.invalidate(tournamentSchedulesProvider);
      return true;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return false;
    }
  }

  Future<TournamentSchedule?> publish(String tournamentId) => _run(
    () => ref
        .read(tournamentScheduleRepositoryProvider)
        .publishTournament(tournamentId),
  );

  Future<TournamentSchedule?> _run(
    Future<TournamentSchedule> Function() action,
  ) async {
    state = const AsyncLoading();
    try {
      final result = await action();
      state = const AsyncData(null);
      ref.invalidate(tournamentSchedulesProvider);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return null;
    }
  }
}

final tournamentManagementControllerProvider =
    AsyncNotifierProvider.autoDispose<TournamentManagementController, void>(
      TournamentManagementController.new,
    );
