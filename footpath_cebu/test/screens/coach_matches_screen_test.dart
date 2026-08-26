import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/data/repositories/mock_match_repository.dart';
import 'package:footpath_cebu/presentation/screens/coach_matches_screen.dart';
import 'package:footpath_cebu/presentation/screens/edit_football_match_screen.dart';

void main() {
  testWidgets('coach sees recorded matches and can open the create form', (
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

    expect(find.text('Match Records'), findsOneWidget);
    expect(find.text('vs Cebu United'), findsOneWidget);
    expect(find.text('3–1'), findsOneWidget);

    await tester.tap(find.text('Record Match'));
    await tester.pumpAndSettle();

    expect(find.byType(EditFootballMatchScreen), findsOneWidget);
    expect(find.text('Opponent'), findsWidgets);
  });
}
