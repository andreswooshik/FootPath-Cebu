import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/presentation/providers/injury_providers.dart';
import 'package:footpath_cebu/presentation/providers/match_providers.dart';
import 'package:footpath_cebu/presentation/screens/coordinator_operations_screen.dart';

void main() {
  Future<void> pumpOperations(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clubInjuriesProvider.overrideWith((ref) async => []),
          footballMatchesProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(home: CoordinatorOperationsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('injury reviews can return to Operations', (tester) async {
    await pumpOperations(tester);

    await tester.tap(find.text('Injury reviews'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Injuries'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Operations'), findsOneWidget);
  });

  testWidgets('match statistics can return to Operations', (tester) async {
    await pumpOperations(tester);

    await tester.tap(find.text('Match statistics'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Match Statistics'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Operations'), findsOneWidget);
  });
}
