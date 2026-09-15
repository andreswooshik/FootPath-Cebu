import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/domain/entities/player_stats.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/domain/repositories/player_stats_repository.dart';
import 'package:footpath_cebu/presentation/screens/coach_assessment_hub_screen.dart';

class _StatsRepository implements PlayerStatsRepository {
  const _StatsRepository(this.stats);

  final PlayerStats stats;

  @override
  Future<PlayerStats> fetchStats(
    String playerId, {
    bool forceRefresh = false,
  }) async => stats;

  @override
  Future<PlayerStatsSaveResult> saveAssessment(
    String playerId,
    PlayerStatsDraft draft,
  ) => throw UnimplementedError();
}

const _coach = UserProfile(
  id: 'coach-1',
  email: 'coach@example.com',
  firstName: 'Coach',
  lastName: 'Reyes',
  role: 'COACH',
  roleDisplay: 'Coach',
);

Player _player({PlayerPosition? position = PlayerPosition.centralMidfielder}) =>
    Player(
      id: 'p1',
      name: 'Liam Tan',
      age: 15,
      classYear: 'Class of 2028',
      ageTier: AgeTier.development,
      position: position,
      ratings: const PlayerRatings(
        pace: 0,
        shooting: 0,
        passing: 0,
        dribbling: 0,
        defending: 0,
        physical: 0,
      ),
      eligibility: EligibilityStatus.eligible,
    );

PlayerStats _stats() => PlayerStats.fromJson({
  'catalog': {
    'version': 1,
    'position': 'CM',
    'roleGroup': 'MIDFIELDER',
    'attributes': [
      'Pace',
      'Passing',
      'Dribbling',
      'Vision',
      'Defending',
      'Physical',
    ],
  },
  'latestCompatibleStats': {
    'id': 'stats-1',
    'position': 'CM',
    'roleGroup': 'MIDFIELDER',
    'catalogVersion': 1,
    'scores': {
      'pace': 80,
      'passing': 81,
      'dribbling': 82,
      'vision': 83,
      'defending': 84,
      'physical': 85,
    },
    'overall': 83,
    'reason': 'MONTHLY_REVIEW',
    'coachNotes': 'Current attributes.',
    'createdAt': '2026-09-01T10:00:00Z',
  },
  'comparison': {'baseline': true},
  'history': [],
  'legacyStatsHistory': [],
});

Future<void> _pump(
  WidgetTester tester,
  Player player, {
  PlayerStatsRepository? repository,
  Size size = const Size(800, 1280),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (repository != null)
          playerStatsRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        home: CoachAssessmentHubScreen(player: player, profile: _coach),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows both assessment systems in one coach workspace', (
    tester,
  ) async {
    await _pump(tester, _player(), repository: _StatsRepository(_stats()));

    expect(find.text('Assess Player'), findsOneWidget);
    expect(find.text('Liam Tan'), findsOneWidget);
    expect(find.text('Card Attributes · 0–99'), findsOneWidget);
    expect(find.text('Update attributes'), findsOneWidget);
    expect(find.text('Development Assessment · 1–5'), findsOneWidget);
    expect(find.text('Create development assessment'), findsOneWidget);
    expect(find.textContaining('Pace 80'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gates Player Stats until the coach assigns a position', (
    tester,
  ) async {
    await _pump(tester, _player(position: null));

    expect(find.text('Position required'), findsOneWidget);
    expect(
      find.text('Assign a position to unlock the correct attribute catalog.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('assessment-position-action')), findsOneWidget);
    expect(find.byKey(const Key('assess-card-attributes')), findsNothing);
  });

  testWidgets('remains usable at SM-X200 landscape dimensions', (tester) async {
    await _pump(
      tester,
      _player(),
      repository: _StatsRepository(_stats()),
      size: const Size(1280, 800),
    );

    expect(find.text('Assess Player'), findsOneWidget);
    expect(find.byKey(const Key('assess-card-attributes')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
