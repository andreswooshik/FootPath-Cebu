import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';
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

      final container = ProviderContainer(
        overrides: [
          scheduleNowProvider.overrideWithValue(now),
          trainingSessionsProvider.overrideWith(
            (ref) async => [
              endedToday,
              stillRunning,
              tomorrow,
              completedTomorrow,
            ],
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(trainingSessionsProvider.future);

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
}
