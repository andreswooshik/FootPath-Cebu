import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/presentation/screens/schedule_session_screen.dart';

void main() {
  /// The form is a lazy ListView, so anything below the fold is never built
  /// and can't be found. Give it a surface tall enough to hold the whole form
  /// rather than scrolling before every assertion.
  Future<void> pumpForm(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ScheduleSessionScreen())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers an All Tiers chip and one chip per tier', (tester) async {
    await pumpForm(tester);

    expect(find.widgetWithText(FilterChip, 'All Tiers'), findsOneWidget);
    expect(
      find.widgetWithText(FilterChip, 'Foundation · Ages 10–12'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilterChip, 'Development · Ages 13–15'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilterChip, 'Pathway · Ages 16–18'),
      findsOneWidget,
    );
  });

  testWidgets('starts with no tier chosen and says so', (tester) async {
    await pumpForm(tester);

    expect(
      find.text('Pick at least one tier — this decides who can attend.'),
      findsOneWidget,
    );
  });

  testWidgets('stacks time fields on a compact phone layout', (tester) async {
    await pumpForm(tester);

    expect(
      find.byKey(const Key('session-time-fields-stacked')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('session-time-fields-inline')), findsNothing);
  });

  testWidgets('places time fields inline when enough width is available', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ScheduleSessionScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('session-time-fields-inline')), findsOneWidget);
  });

  testWidgets('tiers are multi-select, not one-of', (tester) async {
    await pumpForm(tester);

    await tester.tap(
      find.widgetWithText(FilterChip, 'Foundation · Ages 10–12'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Pathway · Ages 16–18'));
    await tester.pumpAndSettle();

    // Both stay selected — picking a second tier must not drop the first.
    expect(
      find.text('Only Foundation and Pathway players can be marked present.'),
      findsOneWidget,
    );
  });

  testWidgets('All Tiers selects every tier, then clears', (tester) async {
    await pumpForm(tester);

    await tester.tap(find.widgetWithText(FilterChip, 'All Tiers'));
    await tester.pumpAndSettle();
    expect(find.text('Open to every player in the academy.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'All Tiers'));
    await tester.pumpAndSettle();
    expect(
      find.text('Pick at least one tier — this decides who can attend.'),
      findsOneWidget,
    );
  });

  testWidgets('selecting every tier individually lights up All Tiers', (
    tester,
  ) async {
    await pumpForm(tester);

    await tester.tap(
      find.widgetWithText(FilterChip, 'Foundation · Ages 10–12'),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilterChip, 'Development · Ages 13–15'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Pathway · Ages 16–18'));
    await tester.pumpAndSettle();

    final allChip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'All Tiers'),
    );
    expect(allChip.selected, isTrue);
    expect(find.text('Open to every player in the academy.'), findsOneWidget);
  });

  testWidgets('cannot schedule without a tier', (tester) async {
    await pumpForm(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'e.g. Tactical Workshop'),
      'Tactical Workshop',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'e.g. USJ-R Basak Pitch'),
      'USJ-R Basak Pitch',
    );
    await tester.tap(find.text('Create Schedule'));
    await tester.pump();

    expect(
      find.text(
        'Complete the title, date, start time, end time, and location.',
      ),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
  });
}
