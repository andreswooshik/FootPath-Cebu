import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/presentation/providers/mutation_controller.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';

/// The full training schedule. Refresh with
/// `ref.refresh(trainingSessionsProvider.future)`; scheduling a new session
/// invalidates this automatically (see [ScheduleSessionController.submit]).
final trainingSessionsProvider =
    FutureProvider.autoDispose<List<TrainingSession>>(
      (ref) => ref.watch(getTrainingSessionsProvider)(),
    );

final eligiblePlayerCountProvider = FutureProvider.autoDispose
    .family<int, String>((ref, tierKey) async {
      final selected = tierKey
          .split('|')
          .where((value) => value.isNotEmpty)
          .map(AgeTierInfo.fromWire)
          .toSet();
      if (selected.isEmpty) return 0;
      final players = await ref.watch(getSquadProvider)();
      return players
          .where((player) => selected.contains(player.ageTier))
          .length;
    });

/// One shared local instant for schedule classification. It is invalidated at
/// the next session-end boundary so an open screen moves the card without a
/// manual refresh. Tests override it to make boundary behavior deterministic.
final scheduleNowProvider = Provider.autoDispose<DateTime>(
  (ref) => DateTime.now(),
);

/// Sessions that have not ended yet, soonest first.
final upcomingSessionsProvider =
    Provider.autoDispose<AsyncValue<List<TrainingSession>>>((ref) {
      final now = ref.watch(scheduleNowProvider);
      return ref.watch(trainingSessionsProvider).whenData((sessions) {
        _refreshAtNextSessionEnd(ref, sessions, now);
        final list = sessions.where((s) => !s.hasEndedAt(now)).toList()
          ..sort((a, b) => a.date.compareTo(b.date));
        return List.unmodifiable(list);
      });
    });

/// Sessions whose end time has passed, most recent first.
final pastSessionsProvider =
    Provider.autoDispose<AsyncValue<List<TrainingSession>>>((ref) {
      final now = ref.watch(scheduleNowProvider);
      return ref.watch(trainingSessionsProvider).whenData((sessions) {
        _refreshAtNextSessionEnd(ref, sessions, now);
        final list = sessions.where((s) => s.hasEndedAt(now)).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        return List.unmodifiable(list);
      });
    });

/// Upcoming sessions that actually target the signed-in/selected player's
/// age category. The club schedule can contain sessions for several tiers;
/// player and guardian portals should not present unrelated training.
final playerUpcomingSessionsProvider = Provider.autoDispose
    .family<AsyncValue<List<TrainingSession>>, AgeTier>((ref, ageTier) {
      return ref
          .watch(upcomingSessionsProvider)
          .whenData(
            (sessions) => List.unmodifiable(
              sessions.where((session) => session.includesTier(ageTier)),
            ),
          );
    });

/// Past counterpart of [playerUpcomingSessionsProvider].
final playerPastSessionsProvider = Provider.autoDispose
    .family<AsyncValue<List<TrainingSession>>, AgeTier>((ref, ageTier) {
      return ref
          .watch(pastSessionsProvider)
          .whenData(
            (sessions) => List.unmodifiable(
              sessions.where((session) => session.includesTier(ageTier)),
            ),
          );
    });

void _refreshAtNextSessionEnd(
  Ref ref,
  List<TrainingSession> sessions,
  DateTime now,
) {
  DateTime? nextEnd;
  for (final session in sessions) {
    if (session.status != TrainingSessionStatus.scheduled) continue;
    final end = session.scheduledEndAt;
    if (end == null || !end.isAfter(now)) continue;
    if (nextEnd == null || end.isBefore(nextEnd)) nextEnd = end;
  }
  if (nextEnd == null) return;

  final timer = Timer(
    nextEnd.difference(now) + const Duration(milliseconds: 1),
    () => ref.invalidate(scheduleNowProvider),
  );
  ref.onDispose(timer.cancel);
}

/// Drives the Schedule New Session form's submit button.
///
/// Owns only the submit state ([AsyncValue] loading/error); the form field
/// values live in the screen and are handed over as a draft [TrainingSession].
class ScheduleSessionController extends MutationController {
  /// Persists [draft]. Returns true on success so the screen can pop back to
  /// the schedule — which refreshes by itself, because this invalidates
  /// [trainingSessionsProvider].
  Future<bool> submit(TrainingSession draft) =>
      _run(() => ref.read(scheduleTrainingSessionProvider)(draft));

  /// Saves changes to an existing session (same success/refresh contract as
  /// [submit]). Named to avoid colliding with [AsyncNotifier.update].
  Future<bool> saveChanges(TrainingSession session) =>
      _run(() => ref.read(updateTrainingSessionProvider)(session));

  /// Cancels (deletes) a scheduled session.
  Future<bool> cancel(String sessionId) =>
      _run(() => ref.read(cancelTrainingSessionProvider)(sessionId));

  Future<bool> _run(Future<Object?> Function() action) async {
    return await runMutation(
          () async {
            await action();
            return true;
          },
          onSuccess: (result) {
            ref.invalidate(trainingSessionsProvider);
          },
        ) ??
        false;
  }
}

final scheduleSessionControllerProvider =
    AsyncNotifierProvider.autoDispose<ScheduleSessionController, void>(
      ScheduleSessionController.new,
    );
