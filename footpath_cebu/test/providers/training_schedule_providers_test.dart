import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/presentation/providers/training_schedule_providers.dart';

TrainingSession _session(String id, Set<AgeTier> tiers) => TrainingSession(
  id: id,
  title: 'Training $id',
  ageTiers: tiers,
  date: DateTime(2026, 8, 30),
  startTime: '02:30 PM',
  endTime: '03:45 PM',
  location: 'Dynamic Herb',
  focus: SessionFocus.technical,
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
}
