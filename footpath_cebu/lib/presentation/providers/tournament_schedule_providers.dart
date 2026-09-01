import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';

final tournamentSchedulesProvider =
    FutureProvider.autoDispose<List<TournamentSchedule>>((ref) {
      return ref.watch(tournamentScheduleRepositoryProvider).fetchSchedules();
    });

class TournamentManagementController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<TournamentSchedule?> create({
    required String title,
    required String venue,
    required DateTime startsOn,
    TournamentDocumentUpload? document,
  }) => _run(
    () => ref
        .read(tournamentScheduleRepositoryProvider)
        .createTournament(
          title: title,
          venue: venue,
          startsOn: startsOn,
          document: document,
        ),
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
    Set<AgeTier> academyTiers = const {},
    bool confirmTrainingCancellations = false,
  }) => _run(
    () => ref
        .read(tournamentScheduleRepositoryProvider)
        .addAgeBracket(
          tournamentId,
          maxAge: maxAge,
          scheduledAt: scheduledAt,
          academyTiers: academyTiers,
          confirmTrainingCancellations: confirmTrainingCancellations,
        ),
  );

  Future<TournamentSchedule?> updateBracket(
    String bracketId, {
    required int maxAge,
    DateTime? scheduledAt,
    Set<AgeTier> academyTiers = const {},
    bool confirmTrainingCancellations = false,
  }) => _run(
    () => ref
        .read(tournamentScheduleRepositoryProvider)
        .updateAgeBracket(
          bracketId,
          maxAge: maxAge,
          scheduledAt: scheduledAt,
          academyTiers: academyTiers,
          confirmTrainingCancellations: confirmTrainingCancellations,
        ),
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

  Future<TournamentSchedule?> addFixture(
    String tournamentId,
    TournamentFixtureDraft fixture, {
    bool confirmTrainingCancellations = false,
  }) => _run(
    () => ref
        .read(tournamentScheduleRepositoryProvider)
        .addFixture(
          tournamentId,
          fixture,
          confirmTrainingCancellations: confirmTrainingCancellations,
        ),
  );

  Future<TournamentSchedule?> updateFixture(
    String fixtureId,
    TournamentFixtureDraft fixture, {
    bool confirmTrainingCancellations = false,
  }) => _run(
    () => ref
        .read(tournamentScheduleRepositoryProvider)
        .updateFixture(
          fixtureId,
          fixture,
          confirmTrainingCancellations: confirmTrainingCancellations,
        ),
  );

  Future<bool> deleteFixture(String fixtureId) => _runVoid(
    () =>
        ref.read(tournamentScheduleRepositoryProvider).deleteFixture(fixtureId),
  );

  Future<TournamentSchedule?> uploadDocument(
    String tournamentId,
    TournamentDocumentUpload document,
  ) => _run(
    () => ref
        .read(tournamentScheduleRepositoryProvider)
        .uploadDocument(tournamentId, document),
  );

  Future<bool> removeDocument(String tournamentId) => _runVoid(
    () => ref
        .read(tournamentScheduleRepositoryProvider)
        .removeDocument(tournamentId),
  );

  Future<bool> deleteTournament(String tournamentId) => _runVoid(
    () => ref
        .read(tournamentScheduleRepositoryProvider)
        .deleteTournament(tournamentId),
  );

  Future<TournamentSchedule?> publish(
    String tournamentId, {
    bool confirmTrainingCancellations = false,
  }) => _run(
    () => ref
        .read(tournamentScheduleRepositoryProvider)
        .publishTournament(
          tournamentId,
          confirmTrainingCancellations: confirmTrainingCancellations,
        ),
  );

  Future<TournamentSchedule?> recordResult(
    String fixtureId,
    TournamentResultDraft result,
  ) => _run(
    () => ref
        .read(tournamentScheduleRepositoryProvider)
        .recordResult(fixtureId, result),
  );

  Future<bool> _runVoid(Future<void> Function() action) async {
    state = const AsyncLoading();
    try {
      await action();
      state = const AsyncData(null);
      ref.invalidate(tournamentSchedulesProvider);
      return true;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return false;
    }
  }

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
