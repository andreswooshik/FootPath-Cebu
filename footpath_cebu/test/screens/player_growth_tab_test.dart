import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/data/repositories/mock_growth_repository.dart';
import 'package:footpath_cebu/presentation/screens/player_growth_tab.dart';
import 'package:footpath_cebu/presentation/theme/app_theme.dart';
import 'package:footpath_cebu/presentation/widgets/performance_trend_chart.dart';

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        growthRepositoryProvider.overrideWithValue(MockGrowthRepository()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: PlayerGrowthTab(playerId: 'p1', playerName: 'Rhobert Ronaldo'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('summarizes growth across regular and tournament matches', (
    tester,
  ) async {
    await _pump(tester, const Size(1000, 2200));

    expect(find.text('All Matches'), findsOneWidget);
    expect(find.text('Regular Matches'), findsOneWidget);
    expect(find.text('Tournaments'), findsOneWidget);
    expect(find.text('Overall growth summary'), findsOneWidget);
    expect(find.text('3 matches included in this comparison.'), findsOneWidget);
    expect(find.text('Current strengths'), findsOneWidget);
    expect(find.text('Skills to improve'), findsOneWidget);
    expect(find.text('Then vs. Now'), findsOneWidget);
    expect(find.text('Your Performance Over Time'), findsOneWidget);
    expect(
      find.text(
        'See how your match rating and skills have changed from earlier matches to your most recent matches.',
      ),
      findsOneWidget,
    );
    expect(find.text('Actionable training recommendations'), findsOneWidget);
    expect(find.byType(PerformanceTrendChart), findsOneWidget);
  });

  testWidgets('filters tournament growth and explains insufficient data', (
    tester,
  ) async {
    await _pump(tester, const Size(430, 1900));

    await tester.tap(find.byKey(const ValueKey('matchFilter-tournaments')));
    await tester.pumpAndSettle();

    expect(
      find.text('1 tournament match included in this comparison.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('not enough data to determine a meaningful trend'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
