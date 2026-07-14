import 'package:footpath_cebu/domain/entities/attendance.dart';

/// Reads a single player's attendance history — used by the Guardian dashboard
/// (a guardian views, but never edits, a child's attendance).
abstract class PlayerAttendanceReader {
  /// Returns the player's attendance records, most recent first.
  Future<List<Attendance>> fetchAttendanceForPlayer(String playerId);
}

/// Aggregate of the attendance reads. Concrete data sources implement this one
/// interface, while each ViewModel depends only on the narrow interface it
/// actually uses (Interface Segregation).
abstract class AttendanceRepository implements PlayerAttendanceReader {}

/// Thrown when an attendance read cannot be completed.
class AttendanceRepositoryException implements Exception {
  AttendanceRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}
