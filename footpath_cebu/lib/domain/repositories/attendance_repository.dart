import 'package:footpath_cebu/domain/entities/attendance.dart';

/// Reads a single player's attendance history — used by the Guardian dashboard
/// (a guardian views, but never edits, a child's attendance).
abstract class PlayerAttendanceReader {
  /// Returns the player's attendance records, most recent first.
  Future<List<Attendance>> fetchAttendanceForPlayer(String playerId);
}

/// Reads every record already logged against one training session, so a coach
/// re-opening a session sees what they marked last time.
abstract class SessionAttendanceReader {
  Future<List<Attendance>> fetchAttendanceForSession(String sessionId);
}

/// Writes a session's attendance. Kept separate from the readers so a
/// view-only consumer (the Guardian dashboard) cannot depend on a write it
/// must never perform — Interface Segregation.
abstract class SessionAttendanceWriter {
  /// Replaces the session's records with [records]. Returns what was saved.
  Future<List<Attendance>> saveSessionAttendance(
    String sessionId,
    List<Attendance> records,
  );
}

/// Aggregate of the attendance reads and writes. Concrete data sources
/// implement this one interface, while each consumer depends only on the
/// narrow interface it actually uses (Interface Segregation).
abstract class AttendanceRepository
    implements
        PlayerAttendanceReader,
        SessionAttendanceReader,
        SessionAttendanceWriter {}

/// Thrown when an attendance read or write cannot be completed.
class AttendanceRepositoryException implements Exception {
  AttendanceRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A connection-level failure — the server was never reached (offline, DNS,
/// timeout). Kept distinct from the base exception so the offline-first
/// decorator can queue these for later sync while still propagating HTTP-level
/// failures (e.g. a 400 the coach can fix) immediately.
class AttendanceNetworkException extends AttendanceRepositoryException {
  AttendanceNetworkException(super.message);
}
