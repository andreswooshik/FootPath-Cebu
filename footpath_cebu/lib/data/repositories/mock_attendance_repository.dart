import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';

/// In-memory attendance history for UI development without a backend. Seeded
/// for the two players a guardian is linked to (p2, p3 in
/// [MockPlayerRepository.fetchLinkedPlayers]).
class MockAttendanceRepository implements AttendanceRepository {
  static final List<Attendance> _records = [
    // p2 — Ralf Andre Messi
    Attendance(
      playerId: 'p2',
      status: AttendanceStatus.present,
      updatedAt: DateTime(2026, 7, 8),
      sessionName: 'Evening Training',
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
    ),
  ];

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
