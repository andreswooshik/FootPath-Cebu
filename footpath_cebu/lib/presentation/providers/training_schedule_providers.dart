import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Sessions from today onward, soonest first.
final upcomingSessionsProvider =
    Provider.autoDispose<AsyncValue<List<TrainingSession>>>((ref) {
      return ref.watch(trainingSessionsProvider).whenData((sessions) {
        final list = sessions.where((s) => !_isPast(s.date)).toList()
          ..sort((a, b) => a.date.compareTo(b.date));
        return List.unmodifiable(list);
      });
    });

/// Sessions before today, most recent first.
final pastSessionsProvider =
    Provider.autoDispose<AsyncValue<List<TrainingSession>>>((ref) {
      return ref.watch(trainingSessionsProvider).whenData((sessions) {
        final list = sessions.where((s) => _isPast(s.date)).toList()
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

bool _isPast(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return date.isBefore(today);
}

/// Drives the Schedule New Session form's submit button.
///
/// Owns only the submit state ([AsyncValue] loading/error); the form field
/// values live in the screen and are handed over as a draft [TrainingSession].
class ScheduleSessionController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

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
    state = const AsyncLoading();
    try {
      await action();
      state = const AsyncData(null);
      ref.invalidate(trainingSessionsProvider);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}

final scheduleSessionControllerProvider =
    AsyncNotifierProvider.autoDispose<ScheduleSessionController, void>(
      ScheduleSessionController.new,
    );
