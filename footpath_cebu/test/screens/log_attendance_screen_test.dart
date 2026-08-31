import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';
import 'package:footpath_cebu/presentation/screens/log_attendance_screen.dart';

const _coach = UserProfile(
  id: 'c1',
  email: 'coach@example.com',
  firstName: 'Ralf',
  lastName: 'Cruz',
  role: 'COACH',
  roleDisplay: 'Coach',
);

// Defaults to today so attendance can be logged — the coach may log from the
// session day through two days after (TrainingSession.isAttendanceOpen). Tests
// exercising the window gate pass an explicit past/future date.
TrainingSession _session(Set<AgeTier> tiers, {DateTime? date}) =>
    TrainingSession(
      id: 't1',
      title: 'Technical Drills',
      ageTiers: tiers,
      date: date ?? DateTime.now(),
      startTime: '06:00 AM',
      endTime: '08:00 AM',
      location: 'Dynamic Herb Sports Complex',
      focus: SessionFocus.technical,
    );

class _DelayedAttendanceRepository implements AttendanceRepository {
  final sessionRecords = Completer<List<Attendance>>();

  @override
  Future<List<Attendance>> fetchAttendanceForSession(String sessionId) =>
      sessionRecords.future;

  @override
  Future<List<Attendance>> fetchAttendanceForPlayer(
    String playerId, {
    String? unlockToken,
  }) async => const [];

  @override
  Future<List<Attendance>> saveSessionAttendance(
    String sessionId,
    List<Attendance> records,
  ) async => records;
}

class _RecordingAttendanceRepository implements AttendanceRepository {
  List<Attendance>? savedRecords;

  @override
  Future<List<Attendance>> fetchAttendanceForSession(String sessionId) async =>
      const [];

  @override
  Future<List<Attendance>> fetchAttendanceForPlayer(
    String playerId, {
    String? unlockToken,
  }) async => const [];

  @override
  Future<List<Attendance>> saveSessionAttendance(
    String sessionId,
    List<Attendance> records,
  ) async {
    savedRecords = records;
    return records;
  }
}

void main() {
  /// Tall surface: the roster is a lazy ListView, so cards below the fold are
  /// never built and can't be found. Repository providers default to the
  /// in-memory mocks in a test environment.
  Future<void> pump(
    WidgetTester tester, {
    Set<AgeTier>? tiers,
    DateTime? date,
  }) async {
    await tester.binding.setSurfaceSize(const Size(520, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: LogAttendanceScreen(
            session: _session(tiers ?? {AgeTier.foundation}, date: date),
            profile: _coach,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('never paints an unmarked roster before saved records arrive', (
    tester,
  ) async {
    final repository = _DelayedAttendanceRepository();
    await tester.binding.setSurfaceSize(const Size(520, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [attendanceRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: LogAttendanceScreen(
            session: _session({AgeTier.foundation}),
            profile: _coach,
          ),
        ),
      ),
    );
    // Let the mock squad resolve while attendance deliberately remains in
    // flight. The UI must not claim that every player is unmarked.
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Unmarked'), findsNothing);
    expect(find.text('0 of 2 marked'), findsNothing);
    expect(find.text('Complete Training Session'), findsNothing);

    repository.sessionRecords.complete([
      Attendance(
        playerId: 'p9',
        status: AttendanceStatus.present,
        updatedAt: DateTime.now(),
        sessionId: 't1',
        sessionName: 'Technical Drills',
        effort: 85,
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('1 of 2 marked'), findsOneWidget);
    expect(find.text('1 still unmarked'), findsOneWidget);
    expect(find.text('Effort / Intensity'), findsOneWidget);
  });

  testWidgets('shows the session details in the header', (tester) async {
    await pump(tester, date: DateTime(2026, 6, 28));

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

  testWidgets('the evaluation appears only once a player is present', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Effort / Intensity'), findsNothing);

    await tester.tap(find.text('Present').first);
    await tester.pumpAndSettle();
    expect(find.text('Effort / Intensity'), findsOneWidget);
    expect(find.text('Full assessment'), findsOneWidget);
    expect(find.text('1 of 2 marked'), findsOneWidget);
  });

  testWidgets('records an optional performance score separately from effort', (
    tester,
  ) async {
    final repository = _RecordingAttendanceRepository();
    await tester.binding.setSurfaceSize(const Size(520, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [attendanceRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LogAttendanceScreen(
                      session: _session({AgeTier.foundation}),
                      profile: _coach,
                    ),
                  ),
                ),
                child: const Text('Open attendance'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open attendance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark all present'));
    await tester.pumpAndSettle();

    expect(find.text('Training performance score'), findsNWidgets(2));
    await tester.tap(find.text('Training performance score').first);
    await tester.pumpAndSettle();
    final performanceSlider = tester.widget<Slider>(find.byType(Slider).at(1));
    performanceSlider.onChanged!(8.4);
    await tester.pump();
    await tester.tap(find.textContaining('Complete Training Session'));
    await tester.pumpAndSettle();

    expect(repository.savedRecords, isNotNull);
    expect(repository.savedRecords!.first.performanceScore, 8.4);
    expect(repository.savedRecords!.first.effort, 70);
    expect(repository.savedRecords!.last.performanceScore, isNull);
  });

  testWidgets('an absent player gets no evaluation', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Absent').first);
    await tester.pumpAndSettle();

    expect(find.text('Effort / Intensity'), findsNothing);
    expect(find.text('1 of 2 marked'), findsOneWidget);
  });

  testWidgets('marking present then excused collapses the evaluation again', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Present').first);
    await tester.pumpAndSettle();
    expect(find.text('Effort / Intensity'), findsOneWidget);

    await tester.tap(find.text('Excused').first);
    await tester.pumpAndSettle();
    expect(find.text('Effort / Intensity'), findsNothing);
  });

  testWidgets('mark all present completes the roll call in one tap', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Mark all present'));
    await tester.pumpAndSettle();

    expect(find.text('2 of 2 marked'), findsOneWidget);
    expect(find.text('Unmarked'), findsNothing);
    expect(find.text('Effort / Intensity'), findsNWidgets(2));
    // Nothing left to bulk-fill, so the shortcut retires itself.
    expect(find.text('Mark all present'), findsNothing);
  });

  testWidgets('the finalise button is disabled until something is marked', (
    tester,
  ) async {
    await pump(tester);

    final disabled = find.widgetWithText(
      FilledButton,
      'Complete Training Session',
    );
    expect(tester.widget<FilledButton>(disabled).onPressed, isNull);

    await tester.tap(find.text('Present').first);
    await tester.pumpAndSettle();

    final enabled = find.widgetWithText(
      FilledButton,
      'Complete Training Session (1 present)',
    );
    expect(tester.widget<FilledButton>(enabled).onPressed, isNotNull);
  });

  testWidgets('attendance is locked outside the log window', (tester) async {
    // More than two days after the session: the button is disabled and
    // labelled, even after marking a player present.
    await pump(tester, date: DateTime.now().subtract(const Duration(days: 5)));

    await tester.tap(find.text('Present').first);
    await tester.pumpAndSettle();

    final locked = find.widgetWithText(
      FilledButton,
      'Available on the session day',
    );
    expect(locked, findsOneWidget);
    expect(tester.widget<FilledButton>(locked).onPressed, isNull);
    expect(
      find.text(
        'Attendance can only be logged on the session day or up to '
        '2 days after.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('attendance stays open up to two days after the session', (
    tester,
  ) async {
    // Two days after is still within the grace window — the roll call saves.
    await pump(tester, date: DateTime.now().subtract(const Duration(days: 2)));

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

  testWidgets('a complete roll call saves and returns to the caller', (
    tester,
  ) async {
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

  testWidgets('leaving with unsaved marks asks before discarding', (
    tester,
  ) async {
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

  testWidgets('a multi-tier session pools every eligible player', (
    tester,
  ) async {
    await pump(tester, tiers: {AgeTier.foundation, AgeTier.pathway});

    expect(find.text('6 players'), findsOneWidget);
    expect(find.text('Lamine Yamashita'), findsOneWidget); // Foundation
    expect(find.text('Rhobert Ronaldo'), findsOneWidget); // Pathway
    expect(find.text('Ralf Andre Messi'), findsNothing); // Development
  });
}
