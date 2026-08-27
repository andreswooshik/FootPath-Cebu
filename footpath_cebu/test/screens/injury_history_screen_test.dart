import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/presentation/screens/injury_history_screen.dart';

void main() {
  /// Repository providers default to the in-memory mocks in a test
  /// environment; the mock seeds two confirmed injuries for player p1.
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

  testWidgets('lists the player\'s injuries with status chips', (tester) async {
    await pump(tester);

    expect(find.text('Injuries - Rhobert Ronaldo'), findsOneWidget);
    expect(find.text('Sprained ankle'), findsOneWidget);
    expect(find.text('Bruised knee'), findsOneWidget);
    expect(find.text('Recovering'), findsOneWidget);
    expect(find.text('Recovered'), findsOneWidget);
    expect(find.text('Confirmed'), findsNWidgets(2));
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
      find.text('No injury reports. Tap "Report Injury" to submit one.'),
      findsOneWidget,
    );
  });

  testWidgets('the player can add an injury end-to-end', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Report Injury'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Description *'),
      'Hamstring strain',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Submit Report'));
    await tester.pumpAndSettle();

    expect(
      find.text('Injury report submitted for confirmation.'),
      findsOneWidget,
    );
    expect(find.text('Hamstring strain'), findsOneWidget);
    expect(find.text('Pending confirmation'), findsOneWidget);
  });

  testWidgets('an empty description blocks the save', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Report Injury'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Submit Report'));
    await tester.pumpAndSettle();

    expect(find.text('A description is required.'), findsOneWidget);
    // The sheet stayed open — nothing was saved.
    expect(find.widgetWithText(FilledButton, 'Submit Report'), findsOneWidget);
  });

  testWidgets('confirmed injuries use the recovery approval workflow', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Sprained ankle'));
    await tester.pumpAndSettle();

    expect(find.text('Request Recovery Update'), findsOneWidget);
    expect(
      find.text('The Coordinator must approve this change.'),
      findsOneWidget,
    );
    expect(find.text('Submit Update'), findsOneWidget);
  });

  testWidgets('read-only mode hides the FAB and blocks editing', (
    tester,
  ) async {
    await pump(tester, readOnly: true);

    expect(find.text('Report Injury'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.text('Sprained ankle'));
    await tester.pumpAndSettle();
    expect(find.text('Request Recovery Update'), findsNothing);
  });
}
