import 'package:footpath_cebu/data/local/attendance_outbox.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';

/// Decorator that makes attendance capture survive being offline.
///
/// Wraps the live [AttendanceRepository] (normally [ApiAttendanceRepository])
/// and a durable [AttendanceOutbox]. Only connection-level failures are
/// queued — a validation failure (HTTP 4xx) is a coach-fixable error and
/// propagates immediately rather than being silently retried forever.
/// [AttendanceSyncService] drains the queue when connectivity returns.
class OfflineFirstAttendanceRepository implements AttendanceRepository {
  OfflineFirstAttendanceRepository({
    required this._inner,
    required this._outbox,
  });

  final AttendanceRepository _inner;
  final AttendanceOutbox _outbox;

  @override
  Future<List<Attendance>> saveSessionAttendance(
    String sessionId,
    List<Attendance> records,
  ) async {
    try {
      return await _inner.saveSessionAttendance(sessionId, records);
    } on AttendanceNetworkException {
      // Offline: queue the whole batch and report the coach's marks back as
      // saved — the sync service replays them when the connection returns.
      await _outbox.enqueue(sessionId, records);
      return records;
    }
  }

  @override
  Future<List<Attendance>> fetchAttendanceForSession(String sessionId) async {
    try {
      return await _inner.fetchAttendanceForSession(sessionId);
    } on AttendanceRepositoryException {
      // Offline (or the server errored): show the coach what they last
      // queued for this session rather than an empty roll call.
      final queued = await _outbox.latestBatchForSession(sessionId);
      if (queued != null) return queued.records;
      rethrow;
    }
  }

  @override
  Future<List<Attendance>> fetchAttendanceForPlayer(String playerId) {
    // The offline requirement covers capture only; history reads stay live.
    return _inner.fetchAttendanceForPlayer(playerId);
  }
}
