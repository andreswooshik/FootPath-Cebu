import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/presentation/providers/training_schedule_providers.dart';
import 'package:footpath_cebu/presentation/screens/schedule_session_screen.dart';

TrainingSession _existingSession() => TrainingSession(
  id: 'session-1',
  title: 'Existing Session',
  ageTiers: {AgeTier.development},
  date: DateTime.now().add(const Duration(days: 2)),
  startTime: '04:30 PM',
  endTime: '06:00 PM',
  location: 'Main Pitch',
  focus: SessionFocus.technical,
  sessionObjectives: 'Improve passing speed',
  equipmentRequirements: 'Balls and cones',
  coachInstructions: 'Split into two groups',
);

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
    await tester.tap(find.text('Schedule Session'));
    await tester.pump();

    expect(
      find.text('Complete the required fields before reviewing this session.'),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('prefills saved details and parses existing duration', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eligiblePlayerCountProvider(
            'DEVELOPMENT',
          ).overrideWith((ref) => Future.value(1)),
        ],
        child: MaterialApp(
          home: ScheduleSessionScreen(existing: _existingSession()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('1 hr 30 min'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(
      fields.any((field) => field.controller?.text == 'Improve passing speed'),
      isTrue,
    );
    expect(
      fields.any((field) => field.controller?.text == 'Balls and cones'),
      isTrue,
    );
    expect(
      fields.any((field) => field.controller?.text == 'Split into two groups'),
      isTrue,
    );
  });

  testWidgets('shows deduplicated recent title and location suggestions', (
    tester,
  ) async {
    final first = _existingSession();
    final second = TrainingSession(
      id: 'session-2',
      title: 'existing session',
      ageTiers: {AgeTier.pathway},
      date: DateTime.now().add(const Duration(days: 3)),
      startTime: '05:00 PM',
      endTime: '06:00 PM',
      location: 'Main Pitch',
      focus: SessionFocus.physical,
    );
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ScheduleSessionScreen(recentSessions: [first, second]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Existing Session'), findsOneWidget);
    expect(find.text('Main Pitch'), findsOneWidget);
    expect(find.text('existing session'), findsNothing);

    await tester.tap(find.text('Existing Session').last);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Existing Session',
    );
  });

  testWidgets('uses a safe sticky action area on phone and tablet', (
    tester,
  ) async {
    await pumpForm(tester);
    expect(find.byType(SafeArea), findsWidgets);
    expect(find.text('Schedule Session'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(900, 1200));
    await tester.pump();
    expect(find.text('Schedule Session'), findsOneWidget);
  });

  testWidgets('reviews every saved edit detail before confirmation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eligiblePlayerCountProvider(
            'DEVELOPMENT',
          ).overrideWith((ref) => Future.value(1)),
        ],
        child: MaterialApp(
          home: ScheduleSessionScreen(existing: _existingSession()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.text('Review Changes'), findsOneWidget);
    expect(find.text('Session title: Existing Session'), findsOneWidget);
    expect(find.text('Location: Main Pitch'), findsOneWidget);
    expect(
      find.text('Session objectives: Improve passing speed'),
      findsOneWidget,
    );
    expect(
      find.text('Equipment requirements: Balls and cones'),
      findsOneWidget,
    );
    expect(
      find.text('Coach instructions: Split into two groups'),
      findsOneWidget,
    );
    expect(
      find.text('Conflict check: final validation runs again during save.'),
      findsOneWidget,
    );
    expect(find.text('Confirm Changes'), findsOneWidget);
  });
}
