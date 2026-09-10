import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/page_slice.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/domain/repositories/training_repository.dart';
import 'package:footpath_cebu/presentation/providers/training_schedule_providers.dart';

TrainingSession _session(
  String id,
  Set<AgeTier> tiers, {
  DateTime? date,
  String endTime = '03:45 PM',
  TrainingSessionStatus status = TrainingSessionStatus.scheduled,
}) => TrainingSession(
  id: id,
  title: 'Training $id',
  ageTiers: tiers,
  date: date ?? DateTime(2026, 8, 30),
  startTime: '02:30 PM',
  endTime: endTime,
  location: 'Dynamic Herb',
  focus: SessionFocus.technical,
  status: status,
);

class _PageTrainingRepository implements TrainingRepository {
  _PageTrainingRepository(this.sessions);

  final List<TrainingSession> sessions;
  final requestedOffsets = <int>[];

  @override
  Future<PageSlice<TrainingSession>> fetchSessionPage({
    required TrainingSessionPeriod period,
    required int offset,
    required int limit,
  }) async {
    requestedOffsets.add(offset);
    return PageSlice(items: sessions, nextOffset: offset == 0 ? limit : null);
  }

  @override
  Future<List<TrainingSession>> fetchSessions() async => sessions;

  @override
  Future<TrainingSession> createSession(TrainingSession draft) async => draft;

  @override
  Future<void> deleteSession(String id) async {}

  @override
  Future<TrainingSession> updateSession(TrainingSession session) async =>
      session;
}

void main() {
  test('player schedules contain only sessions for the player age tier', () {
    final allTiers = _session('all', AgeTier.values.toSet());
    final foundation = _session('foundation', {AgeTier.foundation});
    final development = _session('development', {AgeTier.development});

    final container = ProviderContainer(
      overrides: [
        upcomingSessionsProvider.overrideWith(
          (ref) => AsyncData([allTiers, foundation, development]),
        ),
        pastSessionsProvider.overrideWith(
          (ref) => AsyncData([development, foundation, allTiers]),
        ),
      ],
    );
    addTearDown(container.dispose);

    final upcoming = container.read(
      playerUpcomingSessionsProvider(AgeTier.foundation),
    );
    final past = container.read(
      playerPastSessionsProvider(AgeTier.development),
    );

    expect(upcoming.requireValue.map((session) => session.id), [
      'all',
      'foundation',
    ]);
    expect(past.requireValue.map((session) => session.id), [
      'development',
      'all',
    ]);
  });

  test(
    'today sessions move from upcoming to past after their end time',
    () async {
      final now = DateTime(2026, 9, 1, 22, 56);
      final endedToday = _session(
        'ended-today',
        {AgeTier.development},
        date: DateTime(2026, 9, 1),
        endTime: '06:30 PM',
      );
      final stillRunning = _session(
        'still-running',
        {AgeTier.development},
        date: DateTime(2026, 9, 1),
        endTime: '11:30 PM',
      );
      final tomorrow = _session(
        'tomorrow',
        {AgeTier.development},
        date: DateTime(2026, 9, 2),
        endTime: '06:30 PM',
      );
      final completedTomorrow = _session(
        'completed',
        {AgeTier.development},
        date: DateTime(2026, 9, 2),
        status: TrainingSessionStatus.completed,
      );
      final repository = _PageTrainingRepository([
        endedToday,
        stillRunning,
        tomorrow,
        completedTomorrow,
      ]);

      final container = ProviderContainer(
        overrides: [
          scheduleNowProvider.overrideWithValue(now),
          trainingRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      await Future.wait([
        container.read(
          trainingSessionPageProvider(TrainingSessionPeriod.upcoming).future,
        ),
        container.read(
          trainingSessionPageProvider(TrainingSessionPeriod.past).future,
        ),
      ]);

      expect(
        container
            .read(upcomingSessionsProvider)
            .requireValue
            .map((session) => session.id),
        ['still-running', 'tomorrow'],
      );
      expect(
        container
            .read(pastSessionsProvider)
            .requireValue
            .map((session) => session.id),
        ['completed', 'ended-today'],
      );
    },
  );

  test('loads later training-session pages only when requested', () async {
    final now = DateTime(2026, 9, 1, 12);
    final repository = _PageTrainingRepository([
      _session('page', {AgeTier.development}, date: DateTime(2026, 9, 2)),
    ]);
    final container = ProviderContainer(
      overrides: [
        scheduleNowProvider.overrideWithValue(now),
        trainingRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final provider = trainingSessionPageProvider(
      TrainingSessionPeriod.upcoming,
    );
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);

    final first = await container.read(provider.future);
    expect(first.items.single.id, 'page');
    expect(repository.requestedOffsets, [0]);

    await container.read(provider.notifier).loadMore();
    expect(repository.requestedOffsets, [0, 50]);
    expect(container.read(provider).requireValue.hasMore, isFalse);
  });
}
