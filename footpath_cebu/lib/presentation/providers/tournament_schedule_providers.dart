import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/presentation/providers/mutation_controller.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';

final tournamentSchedulesProvider =
    FutureProvider.autoDispose<List<TournamentSchedule>>((ref) {
      return ref.watch(tournamentScheduleRepositoryProvider).fetchSchedules();
    });

class TournamentManagementController extends MutationController {
  /// Creates a tournament with its venue, start date, and optional document.
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

  /// Saves changes to tournament details and refreshes the schedule.
  Future<TournamentSchedule?> saveTournament(TournamentSchedule tournament) =>
      _run(
        () => ref
            .read(tournamentScheduleRepositoryProvider)
            .updateTournament(tournament),
      );

  /// Adds an age bracket with its schedule and targeted academy tiers.
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

  /// Updates an age bracket and passes through training-cancellation
  /// confirmation.
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

  /// Deletes an age bracket and refreshes the tournament schedule.
  Future<bool> deleteBracket(String bracketId) async {
    return await runMutation(
          () async {
            await ref
                .read(tournamentScheduleRepositoryProvider)
                .deleteAgeBracket(bracketId);
            return true;
          },
          onSuccess: (result) {
            ref.invalidate(tournamentSchedulesProvider);
          },
        ) ??
        false;
  }

  /// Adds a fixture and passes through training-cancellation confirmation.
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

  /// Updates a fixture and passes through training-cancellation confirmation.
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

  /// Deletes a fixture and refreshes the tournament schedule.
  Future<bool> deleteFixture(String fixtureId) => _runVoid(
    () =>
        ref.read(tournamentScheduleRepositoryProvider).deleteFixture(fixtureId),
  );

  /// Uploads the tournament document and refreshes the schedule.
  Future<TournamentSchedule?> uploadDocument(
    String tournamentId,
    TournamentDocumentUpload document,
  ) => _run(
    () => ref
        .read(tournamentScheduleRepositoryProvider)
        .uploadDocument(tournamentId, document),
  );

  /// Removes the tournament document and refreshes the schedule.
  Future<bool> removeDocument(String tournamentId) => _runVoid(
    () => ref
        .read(tournamentScheduleRepositoryProvider)
        .removeDocument(tournamentId),
  );

  /// Deletes a tournament and refreshes the schedule.
  Future<bool> deleteTournament(String tournamentId) => _runVoid(
    () => ref
        .read(tournamentScheduleRepositoryProvider)
        .deleteTournament(tournamentId),
  );

  /// Publishes the tournament with any required training-cancellation
  /// confirmation.
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

  /// Saves a fixture result and refreshes the tournament schedule.
  Future<TournamentSchedule?> recordResult(
    String fixtureId,
    TournamentResultDraft result,
  ) => _run(
    () => ref
        .read(tournamentScheduleRepositoryProvider)
        .recordResult(fixtureId, result),
  );

  /// Runs a tournament action without a result object; returns whether it
  /// succeeded.
  Future<bool> _runVoid(Future<void> Function() action) async {
    return await runMutation(
          () async {
            await action();
            return true;
          },
          onSuccess: (result) {
            ref.invalidate(tournamentSchedulesProvider);
          },
        ) ??
        false;
  }

  /// Runs a tournament write and refreshes schedules after a successful result.
  Future<TournamentSchedule?> _run(
    Future<TournamentSchedule> Function() action,
  ) async {
    return runMutation(
      () async {
        final result = await action();
        return result;
      },
      onSuccess: (result) {
        ref.invalidate(tournamentSchedulesProvider);
      },
    );
  }
}

final tournamentManagementControllerProvider =
    AsyncNotifierProvider.autoDispose<TournamentManagementController, void>(
      TournamentManagementController.new,
    );
