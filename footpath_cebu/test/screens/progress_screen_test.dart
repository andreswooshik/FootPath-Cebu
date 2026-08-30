import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/data/repositories/mock_match_repository.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';
import 'package:footpath_cebu/presentation/screens/progress_screen.dart';

const _player = Player(
  id: 'player-1',
  name: 'Test Player',
  age: 15,
  classYear: 'Class of 2028',
  ageTier: AgeTier.development,
  position: PlayerPosition.centralMidfielder,
  ratings: PlayerRatings(
    pace: 70,
    shooting: 70,
    passing: 70,
    dribbling: 70,
    defending: 70,
    physical: 70,
  ),
  eligibility: EligibilityStatus.eligible,
);

class _AttendanceRepository implements AttendanceRepository {
  const _AttendanceRepository(this.records);

  final List<Attendance> records;

  @override
  Future<List<Attendance>> fetchAttendanceForPlayer(
    String playerId, {
    String? unlockToken,
  }) async => records.where((record) => record.playerId == playerId).toList();

  @override
  Future<List<Attendance>> fetchAttendanceForSession(String sessionId) =>
      throw UnimplementedError();

  @override
  Future<List<Attendance>> saveSessionAttendance(
    String sessionId,
    List<Attendance> records,
  ) => throw UnimplementedError();
}

void main() {
  testWidgets('shows a latest training effort even without a written note', (
    tester,
  ) async {
    final records = [
      Attendance(
        playerId: _player.id,
        sessionId: 'session-1',
        sessionName: 'Passing',
        status: AttendanceStatus.present,
        effort: 75,
        note: '',
        updatedAt: DateTime(2026, 8, 30),
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          attendanceRepositoryProvider.overrideWithValue(
            _AttendanceRepository(records),
          ),
          matchRepositoryProvider.overrideWithValue(MockMatchRepository()),
        ],
        child: const MaterialApp(home: ProgressScreen(player: _player)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Training Feedback'));
    await tester.pumpAndSettle();

    expect(find.text('Passing'), findsOneWidget);
    expect(find.text('Effort 75%'), findsOneWidget);
    expect(find.text('No written coach feedback.'), findsOneWidget);
    expect(find.text('No coach feedback yet.'), findsNothing);
  });
}
