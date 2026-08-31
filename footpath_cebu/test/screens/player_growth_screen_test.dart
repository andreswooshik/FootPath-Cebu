import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/data/repositories/mock_growth_repository.dart';
import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/match_performance.dart';
import 'package:footpath_cebu/domain/entities/player_growth.dart';
import 'package:footpath_cebu/domain/repositories/growth_repository.dart';
import 'package:footpath_cebu/presentation/screens/player_growth_screen.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';

class _RecordingMockGrowthRepository implements GrowthRepository {
  final queries = <GrowthQuery>[];
  final _delegate = MockGrowthRepository();

  @override
  Future<PlayerGrowth> fetchGrowth(GrowthQuery query) {
    queries.add(query);
    return _delegate.fetchGrowth(query);
  }
}

class _ValueGrowthRepository implements GrowthRepository {
  _ValueGrowthRepository(this.value);
  final PlayerGrowth value;

  @override
  Future<PlayerGrowth> fetchGrowth(GrowthQuery query) async => value;
}

class _ErrorGrowthRepository implements GrowthRepository {
  @override
  Future<PlayerGrowth> fetchGrowth(GrowthQuery query) =>
      Future<PlayerGrowth>.error(const GrowthRepositoryException('Denied.'));
}

class _PendingGrowthRepository implements GrowthRepository {
  final completer = Completer<PlayerGrowth>();

  @override
  Future<PlayerGrowth> fetchGrowth(GrowthQuery query) => completer.future;
}

PlayerGrowth _emptyGrowth({String position = 'CM'}) => PlayerGrowth(
  playerId: 'p1',
  playerName: 'Alex Santos',
  position: position,
  assessmentSummary: null,
  assessments: const [],
  training: const [],
  regularMatches: null,
  tournaments: const [],
);

MatchPerformance _performance({
  MatchCategory category = MatchCategory.other,
  double? rating,
}) => MatchPerformance(
  id: 'performance-1',
  playerId: 'p1',
  playerName: 'Alex Santos',
  match: FootballMatch(
    id: 'match-1',
    opponent: 'Mandaue FC',
    competition: category == MatchCategory.tournament
        ? 'Cebu Youth Cup'
        : 'Friendly',
    playedOn: DateTime(2026, 8, 27),
    venue: MatchVenue.neutral,
    ourScore: 2,
    opponentScore: 1,
    category: category,
    ageBracketLabel: category == MatchCategory.tournament ? 'U16' : null,
  ),
  position: 'GK',
  starter: true,
  minutesPlayed: 90,
  goals: 0,
  assists: 0,
  shots: 0,
  shotsOnTarget: 0,
  passesAttempted: 20,
  passesCompleted: 16,
  tackles: 0,
  interceptions: 1,
  yellowCards: 0,
  redCards: 0,
  saves: 5,
  goalsConceded: 1,
  cleanSheet: false,
  coachRating: rating,
  notes: '',
  ratingStatus: rating == null
      ? MatchRatingStatus.awaitingRating
      : MatchRatingStatus.rated,
);

MatchGrowth _matchGrowth(MatchPerformance row) => MatchGrowth(
  sampleSize: 1,
  summary: MatchPerformanceSummary.fromPerformances([row]),
  metrics: const {},
  history: [row],
);

Future<void> _pump(
  WidgetTester tester,
  GrowthRepository repository, {
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      retry: (retryCount, error) => null,
      overrides: [growthRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(
        home: PlayerGrowthScreen(playerId: 'p1', playerName: 'Alex Santos'),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows categorized tabs and one shared range selector', (
    tester,
  ) async {
    final repository = _RecordingMockGrowthRepository();
    await _pump(tester, repository);

    for (final label in [
      'Overview',
      'Assessments',
      'Training',
      'Matches',
      'Tournaments',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.labelColor, Colors.black);
    expect(tabBar.unselectedLabelColor, const Color(0xFF31453E));
    expect(tabBar.indicatorColor, Colors.white);
    expect(find.text('Last 10 overview'), findsOneWidget);
    expect(find.text('Technical training'), findsOneWidget);
    expect(find.text('Insufficient data'), findsWidgets);

    await tester.tap(find.text('Last 10'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last 5').last);
    await tester.pumpAndSettle();

    expect(repository.queries.last.range, GrowthRange.last5);
    expect(find.text('Last 5 overview'), findsOneWidget);

    await tester.tap(find.text('Assessments'));
    await tester.pumpAndSettle();
    expect(find.text('Monthly review'), findsOneWidget);
    expect(find.text('FootPath Development Framework'), findsOneWidget);
    expect(find.text('Baseline'), findsNothing);
    await tester.tap(find.byKey(const Key('legacyAssessmentsSection')));
    await tester.pumpAndSettle();
    expect(find.text('Baseline'), findsWidgets);

    await tester.tap(find.text('Training'));
    await tester.pumpAndSettle();
    expect(find.text('Technical Training'), findsOneWidget);
    expect(find.textContaining('4 sessions'), findsOneWidget);
  });

  testWidgets('uses goalkeeper metrics and preserves missing chart points', (
    tester,
  ) async {
    final row = _performance();
    final data = _emptyGrowth(position: 'GK');
    final growth = PlayerGrowth(
      playerId: data.playerId,
      playerName: data.playerName,
      position: data.position,
      assessmentSummary: null,
      assessments: const [],
      training: const [],
      regularMatches: _matchGrowth(row),
      tournaments: const [],
    );
    await _pump(tester, _ValueGrowthRepository(growth));

    await tester.tap(find.text('Matches'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coach rating'));
    await tester.pumpAndSettle();

    expect(find.text('Saves per 90'), findsOneWidget);
    expect(find.text('Goals conceded per 90'), findsOneWidget);
    expect(find.text('Goals per 90'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('missing')), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('Not rated'), findsOneWidget);
  });

  testWidgets('renders tournament group record and player fixture history', (
    tester,
  ) async {
    final row = _performance(category: MatchCategory.tournament, rating: 8.2);
    final matchGrowth = _matchGrowth(row);
    final group = TournamentGrowthGroup(
      tournamentId: 'cup-1',
      tournament: 'Cebu Youth Cup',
      ageBracketLabel: 'U16',
      sampleSize: 1,
      summary: matchGrowth.summary,
      wins: 1,
      draws: 0,
      losses: 0,
      growth: matchGrowth,
      history: [row],
    );
    final data = _emptyGrowth();
    final growth = PlayerGrowth(
      playerId: data.playerId,
      playerName: data.playerName,
      position: data.position,
      assessmentSummary: null,
      assessments: const [],
      training: const [],
      regularMatches: null,
      tournaments: [group],
    );
    await _pump(tester, _ValueGrowthRepository(growth));

    await tester.tap(find.text('Tournaments'));
    await tester.pumpAndSettle();
    expect(find.text('Cebu Youth Cup'), findsOneWidget);
    expect(find.textContaining('1 player fixtures'), findsOneWidget);
    await tester.tap(find.text('Cebu Youth Cup'));
    await tester.pumpAndSettle();
    expect(
      find.text('Team record for player fixtures: 1W 0D 0L'),
      findsOneWidget,
    );
    expect(find.textContaining('Mandaue FC'), findsOneWidget);
  });

  testWidgets('shows a loading state while growth is pending', (tester) async {
    await _pump(tester, _PendingGrowthRepository(), settle: false);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(DashboardLoadingState), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('shows repository errors with a retry action', (tester) async {
    await _pump(tester, _ErrorGrowthRepository());
    expect(find.text('Denied.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('shows category-specific empty states', (tester) async {
    await _pump(tester, _ValueGrowthRepository(_emptyGrowth()));
    await tester.tap(find.text('Assessments'));
    await tester.pumpAndSettle();
    expect(find.text('No assessment history'), findsOneWidget);
    await tester.tap(find.text('Tournaments'));
    await tester.pumpAndSettle();
    expect(find.text('No tournament performance yet'), findsOneWidget);
  });
}
