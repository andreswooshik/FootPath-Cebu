import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/screens/log_attendance_screen.dart';

const _coach = UserProfile(
  id: 'c1',
  email: 'coach@example.com',
  firstName: 'Ralf',
  lastName: 'Cruz',
  role: 'COACH',
  roleDisplay: 'Coach',
);

TrainingSession _session(Set<AgeTier> tiers) => TrainingSession(
      id: 't1',
      title: 'Technical Drills',
      ageTiers: tiers,
      date: DateTime(2026, 6, 28),
      startTime: '06:00 AM',
      endTime: '08:00 AM',
      location: 'Dynamic Herb Sports Complex',
      focus: SessionFocus.technical,
    );

void main() {
  /// Tall surface: the roster is a lazy ListView, so cards below the fold are
  /// never built and can't be found. Repository providers default to the
  /// in-memory mocks in a test environment.
  Future<void> pump(WidgetTester tester, {Set<AgeTier>? tiers}) async {
    await tester.binding.setSurfaceSize(const Size(520, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: LogAttendanceScreen(
            session: _session(tiers ?? {AgeTier.foundation}),
            profile: _coach,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the session details in the header', (tester) async {
    await pump(tester);

    expect(find.text('Technical Drills'), findsOneWidget);
    expect(find.text('June 28, 2026 · 06:00 AM - 08:00 AM'), findsOneWidget);
    expect(find.text('Dynamic Herb Sports Complex'), findsOneWidget);
    expect(find.text('Foundation'), findsOneWidget);
    // The mock squad has exactly 2 Foundation players.
    expect(find.text('2 players'), findsOneWidget);
    expect(find.text('0 of 2 marked'), findsOneWidget);
  });

  testWidgets('lists only players in the session tier', (tester) async {
    await pump(tester);

    expect(find.text('Lamine Yamashita'), findsOneWidget);
    expect(find.text('Pedri Villanueva'), findsOneWidget);
    // A Pathway player must not be markable in a Foundation session.
    expect(find.text('Rhobert Ronaldo'), findsNothing);
  });

  testWidgets('players start unmarked', (tester) async {
    await pump(tester);
    expect(find.text('Unmarked'), findsNWidgets(2));
    expect(find.text('2 still unmarked'), findsOneWidget);
  });

  testWidgets('the evaluation appears only once a player is present',
      (tester) async {
    await pump(tester);

    expect(find.text('Effort / Intensity'), findsNothing);

    await tester.tap(find.text('Present').first);
    await tester.pumpAndSettle();
    expect(find.text('Effort / Intensity'), findsOneWidget);
    expect(find.text('Full assessment'), findsOneWidget);
    expect(find.text('1 of 2 marked'), findsOneWidget);
  });

  testWidgets('an absent player gets no evaluation', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Absent').first);
    await tester.pumpAndSettle();

    expect(find.text('Effort / Intensity'), findsNothing);
    expect(find.text('1 of 2 marked'), findsOneWidget);
  });

  testWidgets('marking present then excused collapses the evaluation again',
      (tester) async {
    await pump(tester);

    await tester.tap(find.text('Present').first);
    await tester.pumpAndSettle();
    expect(find.text('Effort / Intensity'), findsOneWidget);

    await tester.tap(find.text('Excused').first);
    await tester.pumpAndSettle();
    expect(find.text('Effort / Intensity'), findsNothing);
  });

  testWidgets('mark all present completes the roll call in one tap',
      (tester) async {
    await pump(tester);

    await tester.tap(find.text('Mark all present'));
    await tester.pumpAndSettle();

    expect(find.text('2 of 2 marked'), findsOneWidget);
    expect(find.text('Unmarked'), findsNothing);
    expect(find.text('Effort / Intensity'), findsNWidgets(2));
    // Nothing left to bulk-fill, so the shortcut retires itself.
    expect(find.text('Mark all present'), findsNothing);
  });

  testWidgets('the finalise button is disabled until something is marked',
      (tester) async {
    await pump(tester);

    final disabled =
        find.widgetWithText(FilledButton, 'Complete Training Session');
    expect(tester.widget<FilledButton>(disabled).onPressed, isNull);

    await tester.tap(find.text('Present').first);
    await tester.pumpAndSettle();

    final enabled = find.widgetWithText(
      FilledButton,
      'Complete Training Session (1 present)',
    );
    expect(tester.widget<FilledButton>(enabled).onPressed, isNotNull);
  });

  testWidgets('finalising with unmarked players warns first', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Present').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Complete Training Session'));
    await tester.pumpAndSettle();

    expect(find.text('Some players are unmarked'), findsOneWidget);

    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();
    // Refusing the warning must not save or leave the screen.
    expect(find.text('Technical Drills'), findsOneWidget);
  });

  testWidgets('a complete roll call saves and returns to the caller',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(520, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    bool? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => LogAttendanceScreen(
                          session: _session({AgeTier.foundation}),
                          profile: _coach,
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark all present'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Complete Training Session'));
    await tester.pumpAndSettle();

    // A full roll call saves with no warning, then pops true so the schedule
    // knows to refresh.
    expect(find.text('Some players are unmarked'), findsNothing);
    expect(result, isTrue);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('leaving with unsaved marks asks before discarding',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(520, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LogAttendanceScreen(
                        session: _session({AgeTier.foundation}),
                        profile: _coach,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Present').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Discard attendance?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Technical Drills'), findsOneWidget);
  });

  testWidgets('a multi-tier session pools every eligible player',
      (tester) async {
    await pump(tester, tiers: {AgeTier.foundation, AgeTier.pathway});

    expect(find.text('6 players'), findsOneWidget);
    expect(find.text('Lamine Yamashita'), findsOneWidget); // Foundation
    expect(find.text('Rhobert Ronaldo'), findsOneWidget); // Pathway
    expect(find.text('Ralf Andre Messi'), findsNothing); // Development
  });
}
