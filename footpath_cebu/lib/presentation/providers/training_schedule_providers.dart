import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/presentation/providers/mutation_controller.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/domain/repositories/training_repository.dart';

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

class TrainingSessionPageState {
  const TrainingSessionPageState({
    required this.items,
    required this.nextOffset,
    this.isLoadingMore = false,
    this.loadMoreError,
  });

  final List<TrainingSession> items;
  final int? nextOffset;
  final bool isLoadingMore;
  final Object? loadMoreError;

  bool get hasMore => nextOffset != null;

  TrainingSessionPageState copyWith({
    bool? isLoadingMore,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) => TrainingSessionPageState(
    items: items,
    nextOffset: nextOffset,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    loadMoreError: clearLoadMoreError
        ? null
        : loadMoreError ?? this.loadMoreError,
  );
}

class TrainingSessionPageController
    extends AsyncNotifier<TrainingSessionPageState> {
  TrainingSessionPageController(this.period);

  static const pageSize = 50;

  final TrainingSessionPeriod period;

  @override
  Future<TrainingSessionPageState> build() => _firstPage();

  Future<TrainingSessionPageState> _firstPage() async {
    final now = ref.watch(scheduleNowProvider);
    final page = await ref.watch(getTrainingSessionPageProvider)(
      period: period,
      offset: 0,
      limit: pageSize,
    );
    final items = _classify(page.items, now);
    _refreshAtNextSessionEnd(ref, items, now);
    return TrainingSessionPageState(items: items, nextOffset: page.nextOffset);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(_firstPage);
    if (ref.mounted) state = result;
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) return;
    state = AsyncData(
      current.copyWith(isLoadingMore: true, clearLoadMoreError: true),
    );
    try {
      final page = await ref.read(getTrainingSessionPageProvider)(
        period: period,
        offset: current.nextOffset!,
        limit: pageSize,
      );
      if (!ref.mounted) return;
      state = AsyncData(
        TrainingSessionPageState(
          items: List.unmodifiable([
            ...current.items,
            ..._classify(page.items, ref.read(scheduleNowProvider)),
          ]),
          nextOffset: page.nextOffset,
        ),
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = AsyncData(
        current.copyWith(isLoadingMore: false, loadMoreError: error),
      );
    }
  }

  List<TrainingSession> _classify(
    List<TrainingSession> sessions,
    DateTime now,
  ) {
    final items =
        sessions.where((session) {
          final ended = session.hasEndedAt(now);
          return period == TrainingSessionPeriod.past ? ended : !ended;
        }).toList()..sort(
          (a, b) => period == TrainingSessionPeriod.past
              ? b.date.compareTo(a.date)
              : a.date.compareTo(b.date),
        );
    return List.unmodifiable(items);
  }
}

final trainingSessionPageProvider = AsyncNotifierProvider.autoDispose
    .family<
      TrainingSessionPageController,
      TrainingSessionPageState,
      TrainingSessionPeriod
    >(TrainingSessionPageController.new);

/// Sessions that have not ended yet, soonest first.
final upcomingSessionsProvider =
    Provider.autoDispose<AsyncValue<List<TrainingSession>>>((ref) {
      return ref
          .watch(trainingSessionPageProvider(TrainingSessionPeriod.upcoming))
          .whenData((page) => page.items);
    });

/// Sessions whose end time has passed, most recent first.
final pastSessionsProvider =
    Provider.autoDispose<AsyncValue<List<TrainingSession>>>((ref) {
      return ref
          .watch(trainingSessionPageProvider(TrainingSessionPeriod.past))
          .whenData((page) => page.items);
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
            ref.invalidate(
              trainingSessionPageProvider(TrainingSessionPeriod.upcoming),
            );
            ref.invalidate(
              trainingSessionPageProvider(TrainingSessionPeriod.past),
            );
          },
        ) ??
        false;
  }
}

final scheduleSessionControllerProvider =
    AsyncNotifierProvider.autoDispose<ScheduleSessionController, void>(
      ScheduleSessionController.new,
    );
