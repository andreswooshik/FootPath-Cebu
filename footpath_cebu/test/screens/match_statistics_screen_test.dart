import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/data/repositories/mock_match_repository.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/presentation/screens/match_statistics_screen.dart';
import 'package:footpath_cebu/presentation/screens/progress_screen.dart';
import 'package:footpath_cebu/presentation/theme/app_theme.dart';
import 'package:footpath_cebu/presentation/widgets/performance_trend_chart.dart';

const _linkedPlayer = Player(
  id: 'p1',
  name: 'Linked Player',
  age: 15,
  classYear: 'Class of 2028',
  ageTier: AgeTier.development,
  position: PlayerPosition.centralMidfielder,
  ratings: PlayerRatings(
    pace: 70,
    shooting: 70,
    passing: 70,
    dribbling: 70,
    defending: 70,
    physical: 70,
  ),
  eligibility: EligibilityStatus.eligible,
);

Widget _app(String playerId) => ProviderScope(
  overrides: [matchRepositoryProvider.overrideWithValue(MockMatchRepository())],
  child: MaterialApp(
    home: Scaffold(body: PlayerMatchStatisticsView(playerId: playerId)),
  ),
);

void main() {
  testWidgets('shows player totals, trend, and match history', (tester) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app('p1'));
    await tester.pumpAndSettle();

    expect(find.text('Last 5 Summary'), findsOneWidget);
    expect(find.text('MATCHES'), findsOneWidget);
    expect(find.byType(PerformanceTrendChart), findsOneWidget);
    expect(find.textContaining('Cebu United'), findsOneWidget);
  });

  testWidgets('shows a clear empty state before coach data exists', (
    tester,
  ) async {
    await tester.pumpWidget(_app('new-player'));
    await tester.pumpAndSettle();

    expect(find.text('No match statistics recorded yet.'), findsOneWidget);
  });

  testWidgets('guardian progress includes the linked player match tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchRepositoryProvider.overrideWithValue(MockMatchRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ProgressScreen(player: _linkedPlayer, isGuardian: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.labelColor, Colors.black);
    expect(tabBar.unselectedLabelColor, Colors.black87);
    expect(tabBar.indicatorColor, Colors.black);
    expect(find.text('Matches'), findsOneWidget);
    expect(find.text('Training Feedback'), findsOneWidget);
    expect(find.text('Last 5 Summary'), findsOneWidget);

    await tester.tap(find.text('Training Feedback'));
    await tester.pumpAndSettle();

    expect(find.text('Matches'), findsOneWidget);
    expect(find.text('Training Feedback'), findsOneWidget);
  });
}
