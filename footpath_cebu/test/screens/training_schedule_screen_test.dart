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
import 'package:footpath_cebu/presentation/providers/training_schedule_providers.dart';
import 'package:footpath_cebu/presentation/screens/training_schedule_screen.dart';

const _coach = UserProfile(
  id: 'c1',
  email: 'coach@example.com',
  firstName: 'Ralf',
  lastName: 'Cruz',
  role: 'COACH',
  roleDisplay: 'Coach',
);

TrainingSession _session(String id, DateTime date) => TrainingSession(
  id: id,
  title: id == 'upcoming' ? 'Upcoming Training' : 'Past Training',
  ageTiers: {AgeTier.development},
  date: date,
  startTime: '02:30 PM',
  endTime: '03:45 PM',
  location: 'Dynamic Herb',
  focus: SessionFocus.technical,
);

class _DelayedAttendanceRepository implements AttendanceRepository {
  final sessionAttendance = Completer<List<Attendance>>();

  @override
  Future<List<Attendance>> fetchAttendanceForSession(String sessionId) =>
      sessionAttendance.future;

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

void main() {
  testWidgets('management actions appear only for upcoming sessions', (
    tester,
  ) async {
    final upcoming = _session(
      'upcoming',
      DateTime.now().add(const Duration(days: 1)),
    );
    final past = _session(
      'past',
      DateTime.now().subtract(const Duration(days: 1)),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          upcomingSessionsProvider.overrideWith((ref) => AsyncData([upcoming])),
          pastSessionsProvider.overrideWith((ref) => AsyncData([past])),
        ],
        child: const MaterialApp(home: TrainingScheduleScreen(profile: _coach)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Upcoming Training'), findsOneWidget);
    expect(find.byTooltip('Manage session'), findsOneWidget);

    await tester.tap(find.text('Past Sessions'));
    await tester.pumpAndSettle();

    expect(find.text('Past Training'), findsOneWidget);
    expect(find.byTooltip('Manage session'), findsNothing);
    expect(find.text('Edit session'), findsNothing);
    expect(find.text('Cancel session'), findsNothing);
  });

  testWidgets('waits for saved attendance before opening the log screen', (
    tester,
  ) async {
    final attendanceRepository = _DelayedAttendanceRepository();
    final upcoming = _session(
      'upcoming',
      DateTime.now().add(const Duration(days: 1)),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          attendanceRepositoryProvider.overrideWithValue(attendanceRepository),
          upcomingSessionsProvider.overrideWith((ref) => AsyncData([upcoming])),
          pastSessionsProvider.overrideWith((ref) => const AsyncData([])),
        ],
        child: const MaterialApp(home: TrainingScheduleScreen(profile: _coach)),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Upcoming Training'));
    await tester.pump();

    expect(find.text('Training Schedule'), findsOneWidget);
    expect(find.text('Opening attendance...'), findsOneWidget);
    expect(find.text('Log Attendance'), findsNothing);

    attendanceRepository.sessionAttendance.complete([
      Attendance(
        playerId: 'p2',
        status: AttendanceStatus.present,
        updatedAt: DateTime.now(),
        sessionId: upcoming.id,
        effort: 88,
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Attendance'), findsOneWidget);
    expect(find.text('1 of 4 marked'), findsOneWidget);
    expect(find.text('Effort / Intensity'), findsOneWidget);
    expect(find.text('0 of 4 marked'), findsNothing);
  });
}
