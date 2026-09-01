import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/data/repositories/mock_player_stats_repository.dart';
import 'package:footpath_cebu/domain/entities/player_stats.dart';
import 'package:footpath_cebu/domain/repositories/player_stats_repository.dart';
import 'package:footpath_cebu/presentation/screens/player_stats_screen.dart';

class _ValuePlayerStatsRepository implements PlayerStatsRepository {
  _ValuePlayerStatsRepository(this.value);

  final PlayerStats value;

  @override
  Future<PlayerStats> fetchStats(
    String playerId, {
    bool forceRefresh = false,
  }) async => value;

  @override
  Future<PlayerStatsSaveResult> saveAssessment(
    String playerId,
    PlayerStatsDraft draft,
  ) => throw UnimplementedError();
}

PlayerStats _emptyStats() => PlayerStats.fromJson({
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
  'latestCompatibleStats': null,
  'comparison': {
    'baseline': true,
    'previousOverall': null,
    'newOverall': null,
    'overallDelta': null,
    'attributes': {},
  },
  'history': [],
  'legacyStatsHistory': [],
  'isBaseline': true,
});

Future<void> _pump(
  WidgetTester tester,
  PlayerStatsRepository repository,
) async {
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [playerStatsRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(
        home: PlayerStatsScreen(playerId: 'p1', playerName: 'Alex Santos'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the catalog attributes and current overall', (
    tester,
  ) async {
    await _pump(tester, MockPlayerStatsRepository());

    expect(find.text('80'), findsWidgets);
    expect(find.text('ATTACKER · ST'), findsOneWidget);
    expect(find.text('Off-ball Movement'), findsOneWidget);
    expect(find.text('Pace'), findsOneWidget);
    expect(find.text('Assessment history'), findsOneWidget);
    expect(find.text('Coach notes'), findsOneWidget);
  });

  testWidgets('shows an explicit empty state before the baseline assessment', (
    tester,
  ) async {
    await _pump(tester, _ValuePlayerStatsRepository(_emptyStats()));

    expect(find.text('No Player Stats assessment yet'), findsOneWidget);
    expect(find.text('Baseline not recorded'), findsOneWidget);
  });
}
