import 'package:footpath_cebu/data/local/attendance_outbox.dart';
import 'package:footpath_cebu/data/local/attendance_write_queue.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';

/// Decorator that makes attendance capture survive being offline.
///
/// Wraps the live [AttendanceRepository] (normally [ApiAttendanceRepository])
/// and a durable [AttendanceOutbox]. Connection failures start a queue; later
/// edits to that session join it to preserve write order. Direct HTTP failures
/// propagate rather than being treated as offline success.
/// [AttendanceSyncService] drains the queue when connectivity returns.
class OfflineFirstAttendanceRepository implements AttendanceRepository {
  OfflineFirstAttendanceRepository({
    required this._inner,
    required this._outbox,
    required this._ownerUid,
    AttendanceWriteQueue? writeQueue,
    this.requestSync,
  }) : _writeQueue = writeQueue ?? AttendanceWriteQueue();

  final AttendanceRepository _inner;
  final AttendanceOutbox _outbox;
  final String? Function() _ownerUid;
  final AttendanceWriteQueue _writeQueue;
  final void Function()? requestSync;

  @override
  Future<List<Attendance>> saveSessionAttendance(
    String sessionId,
    List<Attendance> records,
  ) async {
    final ownerUid = _ownerUid();
    _ensureOwner(ownerUid);
    final saved = await _writeQueue.run(
      () => _save(ownerUid!, sessionId, records),
    );
    _ensureOwner(ownerUid);
    requestSync?.call();
    return saved;
  }

  Future<List<Attendance>> _save(
    String ownerUid,
    String sessionId,
    List<Attendance> records,
  ) async {
    _ensureOwner(ownerUid);
    // If work is already queued, append the newest intent durably before
    // attempting the server. A crash cannot let an older pending intent win.
    final pending = await _outbox.latestBatchForSession(ownerUid, sessionId);
    _ensureOwner(ownerUid);
    if (pending != null) {
      if (pending.isRejected) {
        await _outbox.replaceSession(ownerUid, sessionId, records);
      } else {
        await _outbox.enqueue(ownerUid, sessionId, records);
      }
      _ensureOwner(ownerUid);
      return records;
    }
    try {
      final saved = await _inner.saveSessionAttendance(sessionId, records);
      _ensureOwner(ownerUid);
      return saved;
    } on AttendanceNetworkException {
      // Offline: queue the whole batch and report the coach's marks back as
      // saved — the sync service replays them when the connection returns.
      _ensureOwner(ownerUid);
      await _outbox.enqueue(ownerUid, sessionId, records);
      _ensureOwner(ownerUid);
      return records;
    }
  }

  @override
  Future<List<Attendance>> fetchAttendanceForSession(String sessionId) async {
    final ownerUid = _ownerUid();
    _ensureOwner(ownerUid);
    try {
      final records = await _inner.fetchAttendanceForSession(sessionId);
      _ensureOwner(ownerUid);
      final queued = await _outbox.latestBatchForSession(ownerUid!, sessionId);
      _ensureOwner(ownerUid);
      return queued?.records ?? records;
    } on AttendanceNetworkException {
      // Only a transport failure may use queued data. An HTTP rejection (for
      // example 401/403/500) must remain visible rather than being masked by a
      // stale roll call.
      _ensureOwner(ownerUid);
      final queued = await _outbox.latestBatchForSession(ownerUid!, sessionId);
      _ensureOwner(ownerUid);
      if (queued != null) return queued.records;
      rethrow;
    }
  }

  void _ensureOwner(String? ownerUid) {
    if (ownerUid == null || ownerUid.isEmpty || _ownerUid() != ownerUid) {
      throw AttendanceRepositoryException(
        'The signed-in account changed. Please try again.',
      );
    }
  }

  @override
  Future<List<Attendance>> fetchAttendanceForPlayer(
    String playerId, {
    String? unlockToken,
  }) {
    // The offline requirement covers capture only; history reads stay live.
    return _inner.fetchAttendanceForPlayer(playerId, unlockToken: unlockToken);
  }
}
