import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/data/repositories/mock_match_repository.dart';
import 'package:footpath_cebu/presentation/screens/match_statistics_screen.dart';
import 'package:footpath_cebu/presentation/widgets/performance_trend_chart.dart';

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

    expect(find.text('Season Summary'), findsOneWidget);
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
}
