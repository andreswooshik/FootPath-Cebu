import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';

/// In-memory attendance history for UI development without a backend. Seeded
/// for the signed-in player (p1, [MockPlayerRepository.fetchMyProfile]) and
/// the two players a guardian is linked to (p2, p3 in
/// [MockPlayerRepository.fetchLinkedPlayers]).
class MockAttendanceRepository implements AttendanceRepository {
  static final List<Attendance> _records = [
    // p1 — Rhobert Ronaldo (MockPlayerRepository.fetchMyProfile's stand-in
    // for "the signed-in player")
    Attendance(
      playerId: 'p1',
      status: AttendanceStatus.present,
      updatedAt: DateTime(2026, 7, 9),
      sessionName: 'Finishing Practice',
      effort: 92,
      note: 'Clinical in front of goal. Keep working on weak-foot shots.',
    ),
    Attendance(
      playerId: 'p1',
      status: AttendanceStatus.present,
      updatedAt: DateTime(2026, 7, 4),
      sessionName: 'Match Simulation',
      effort: 80,
      note: 'Composed on the ball under pressure. Strong game sense.',
    ),
    Attendance(
      playerId: 'p1',
      status: AttendanceStatus.excused,
      updatedAt: DateTime(2026, 6, 30),
      sessionName: 'Fitness Drill',
    ),
    // p2 — Ralf Andre Messi
    Attendance(
      playerId: 'p2',
      status: AttendanceStatus.present,
      updatedAt: DateTime(2026, 7, 8),
      sessionName: 'Evening Training',
      effort: 55,
      note: 'Good awareness of teammates. Work on the timing of the '
          'defensive transition.',
    ),
    Attendance(
      playerId: 'p2',
      status: AttendanceStatus.present,
      updatedAt: DateTime(2026, 7, 5),
      sessionName: 'Tactical Session',
    ),
    Attendance(
      playerId: 'p2',
      status: AttendanceStatus.excused,
      updatedAt: DateTime(2026, 7, 1),
      sessionName: 'Fitness Drill',
    ),
    Attendance(
      playerId: 'p2',
      status: AttendanceStatus.absent,
      updatedAt: DateTime(2026, 6, 27),
      sessionName: 'Evening Training',
    ),
    // p3 — Reiner Neymar
    Attendance(
      playerId: 'p3',
      status: AttendanceStatus.present,
      updatedAt: DateTime(2026, 7, 8),
      sessionName: 'Evening Training',
    ),
    Attendance(
      playerId: 'p3',
      status: AttendanceStatus.absent,
      updatedAt: DateTime(2026, 7, 6),
      sessionName: 'Speed & Agility Session',
    ),
    Attendance(
      playerId: 'p3',
      status: AttendanceStatus.present,
      updatedAt: DateTime(2026, 7, 3),
      sessionName: 'Finishing Practice',
      effort: 88,
      note: 'Excellent footwork today. Focus on recovery breathing during '
          'high-intensity intervals.',
    ),
  ];

  @override
  Future<List<Attendance>> fetchAttendanceForSession(String sessionId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return List.unmodifiable(_records.where((a) => a.sessionId == sessionId));
  }

  @override
  Future<List<Attendance>> saveSessionAttendance(
    String sessionId,
    List<Attendance> records,
  ) async {
    await Future.delayed(const Duration(milliseconds: 400));
    // Replace the session's records wholesale, so re-finalising a session
    // corrects it rather than duplicating every player.
    _records.removeWhere((a) => a.sessionId == sessionId);
    _records.addAll(records);
    return List.unmodifiable(records);
  }

  @override
  Future<List<Attendance>> fetchAttendanceForPlayer(String playerId) async {
    // Simulate network latency so loading states are exercised in the UI.
    await Future.delayed(const Duration(milliseconds: 300));
    final records =
        _records.where((a) => a.playerId == playerId).toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(records);
  }
}
