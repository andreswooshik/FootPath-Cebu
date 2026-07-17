import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/presentation/screens/injury_history_screen.dart';

void main() {
  /// Repository providers default to the in-memory mocks in a test
  /// environment; the mock seeds two injuries for player p1. Tall surface so
  /// the whole form sheet (incl. its Delete button) is hit-testable.
  Future<void> pump(WidgetTester tester, {bool readOnly = false}) async {
    await tester.binding.setSurfaceSize(const Size(520, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: InjuryHistoryScreen(
            playerId: 'p1',
            playerName: 'Rhobert Ronaldo',
            readOnly: readOnly,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists the player\'s injuries with status chips',
      (tester) async {
    await pump(tester);

    expect(find.text('Injuries · Rhobert Ronaldo'), findsOneWidget);
    expect(find.text('Sprained ankle'), findsOneWidget);
    expect(find.text('Bruised knee'), findsOneWidget);
    expect(find.text('Recovering'), findsOneWidget);
    expect(find.text('Recovered'), findsOneWidget);
  });

  testWidgets('a player with no records sees the empty state', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: InjuryHistoryScreen(
            playerId: 'p2',
            playerName: 'Ralf Andre Messi',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No injuries logged. Tap "Log Injury" to add one.'),
      findsOneWidget,
    );
  });

  testWidgets('the player can add an injury end-to-end', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Log Injury'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Description *'),
      'Hamstring strain',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Log Injury'));
    await tester.pumpAndSettle();

    expect(find.text('Injury saved.'), findsOneWidget);
    expect(find.text('Hamstring strain'), findsOneWidget);
  });

  testWidgets('an empty description blocks the save', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Log Injury'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Log Injury'));
    await tester.pumpAndSettle();

    expect(find.text('A description is required.'), findsOneWidget);
    // The sheet stayed open — nothing was saved.
    expect(find.widgetWithText(FilledButton, 'Log Injury'), findsOneWidget);
  });

  testWidgets('tapping a record opens the edit form with a delete action',
      (tester) async {
    await pump(tester);

    await tester.tap(find.text('Sprained ankle'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Injury'), findsOneWidget);
    expect(find.text('Delete Injury'), findsOneWidget);

    await tester.tap(find.text('Delete Injury'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this injury?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Injury deleted.'), findsOneWidget);
    expect(find.text('Sprained ankle'), findsNothing);
  });

  testWidgets('read-only mode hides the FAB and blocks editing',
      (tester) async {
    await pump(tester, readOnly: true);

    expect(find.text('Log Injury'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.text('Sprained ankle'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Injury'), findsNothing);
  });
}
