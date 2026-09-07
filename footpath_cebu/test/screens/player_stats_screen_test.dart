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

PlayerStats _historyStats() => PlayerStats.fromJson({
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
    'id': 'new',
    'position': 'CM',
    'roleGroup': 'MIDFIELDER',
    'catalogVersion': 1,
    'scores': {
      'pace': 90,
      'passing': 81,
      'dribbling': 82,
      'vision': 83,
      'defending': 84,
      'physical': 85,
    },
    'overall': 84,
    'reason': 'MONTHLY_REVIEW',
    'coachNotes': 'Sharper movement.',
    'assessedBy': 'Coach Lee',
    'createdAt': '2026-09-05T10:00:00Z',
  },
  'comparison': {
    'baseline': false,
    'previousOverall': 82,
    'newOverall': 84,
    'overallDelta': 2,
    'attributes': {
      'pace': {'previous': 80, 'new': 90, 'delta': 10},
    },
  },
  'history': [
    {
      'id': 'new',
      'position': 'CM',
      'roleGroup': 'MIDFIELDER',
      'catalogVersion': 1,
      'scores': {
        'pace': 90,
        'passing': 81,
        'dribbling': 82,
        'vision': 83,
        'defending': 84,
        'physical': 85,
      },
      'overall': 84,
      'reason': 'MONTHLY_REVIEW',
      'coachNotes': 'Sharper movement.',
      'assessedBy': 'Coach Lee',
      'createdAt': '2026-09-05T10:00:00Z',
    },
    {
      'id': 'old',
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
      'overall': 82,
      'reason': 'GENERAL_REVIEW',
      'coachNotes': 'Baseline notes.',
      'assessedBy': 'Coach Lee',
      'createdAt': '2026-08-05T10:00:00Z',
    },
  ],
  'legacyStatsHistory': [
    {
      'id': 'legacy',
      'position': 'CM',
      'ratings': {
        'pace': 70,
        'passing': 71,
        'dribbling': 72,
        'defending': 73,
        'physical': 74,
        'shooting': 75,
      },
      'overall': 73,
      'assessmentReason': 'BASELINE',
      'assessedByRole': 'Coach',
      'coachNotes': 'Imported legacy record.',
      'createdAt': '2025-08-05T10:00:00Z',
    },
  ],
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

  testWidgets('renders full compatible history, trend, and legacy history', (
    tester,
  ) async {
    await _pump(tester, _ValuePlayerStatsRepository(_historyStats()));

    expect(find.text('Overall trend'), findsOneWidget);
    expect(find.textContaining('CM · MIDFIELDER'), findsNWidgets(2));
    expect(find.textContaining('Pace 80 → 90'), findsOneWidget);
    expect(find.textContaining('+10'), findsOneWidget);
    expect(find.text('Overall 82 · Baseline'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('Legacy Stats History'), findsOneWidget);
    expect(find.text('Read-only FIFA-style ratings'), findsOneWidget);

    await tester.tap(find.text('Legacy Stats History'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.textContaining('pace: 70'), findsOneWidget);
    expect(find.textContaining('Imported legacy record.'), findsOneWidget);
  });

  testWidgets('assessment form starts with blank scores, reason, and notes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: PlayerStatsAssessmentScreen(
            playerId: 'p1',
            playerName: 'Alex Santos',
            stats: _historyStats(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = tester.widgetList<TextFormField>(find.byType(TextFormField));
    expect(
      fields.take(6).every((field) => field.controller!.text.isEmpty),
      isTrue,
    );
    expect(fields.last.controller!.text, isEmpty);
    final reason = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(reason.initialValue, isNull);
  });

  testWidgets('requires a reason before review', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: PlayerStatsAssessmentScreen(
            playerId: 'p1',
            playerName: 'Alex Santos',
            stats: _emptyStats(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    for (var index = 0; index < 6; index++) {
      await tester.enterText(fields.at(index), '80');
    }
    await tester.enterText(fields.last, 'Fresh notes');
    await tester.tap(find.text('Review and Save'));
    await tester.pump();

    expect(find.text('Assessment reason is required.'), findsOneWidget);
    expect(find.text('Confirm Player Stats'), findsNothing);
  });

  test('parses server comparison and legacy assessment responses', () {
    final stats = _historyStats();

    expect(stats.comparison.overallDelta, 2);
    expect(stats.comparison.attributes['pace']!.delta, 10);
    expect(stats.legacyHistory.single.reason, 'BASELINE');
    expect(stats.legacyHistory.single.ratings['pace'], 70);
  });
}
