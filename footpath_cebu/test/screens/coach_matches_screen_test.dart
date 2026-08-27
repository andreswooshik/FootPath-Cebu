import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/data/repositories/mock_match_repository.dart';
import 'package:footpath_cebu/presentation/screens/coach_matches_screen.dart';
import 'package:footpath_cebu/presentation/screens/match_roster_screen.dart';

void main() {
  testWidgets('coach sees recorded matches and opens the rating roster', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchRepositoryProvider.overrideWithValue(MockMatchRepository()),
        ],
        child: const MaterialApp(home: CoachMatchesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Match Ratings'), findsOneWidget);
    expect(find.text('vs Cebu United'), findsOneWidget);
    expect(find.text('3–1'), findsOneWidget);

    expect(find.text('Record Match'), findsNothing);
    await tester.tap(find.text('vs Cebu United'));
    await tester.pumpAndSettle();

    expect(find.byType(MatchRosterScreen), findsOneWidget);
    expect(find.text('Coach Ratings'), findsOneWidget);
  });
}
