import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
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
  Future<bool> submit(TrainingSession draft) async {
    state = const AsyncLoading();
    try {
      await ref.read(scheduleTrainingSessionProvider)(draft);
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
