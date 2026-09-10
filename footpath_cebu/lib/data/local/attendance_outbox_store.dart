import 'package:footpath_cebu/domain/entities/attendance.dart';

class OutboxBatch {
  const OutboxBatch({
    required this.id,
    required this.ownerUid,
    required this.sessionId,
    required this.records,
    required this.retryCount,
    required this.requestId,
    this.expectedRevision,
    this.lastError,
    this.isRejected = false,
  });

  final int id;
  final String ownerUid;
  final String sessionId;
  final List<Attendance> records;
  final int retryCount;
  final String requestId;
  final int? expectedRevision;
  final String? lastError;
  final bool isRejected;
}

abstract class AttendanceOutboxStore {
  Future<int> enqueue(
    String ownerUid,
    String sessionId,
    List<Attendance> records, {
    String? requestId,
    int? expectedRevision,
  });

  Future<List<OutboxBatch>> pendingBatches(String ownerUid);
  Future<OutboxBatch?> latestBatchForSession(String ownerUid, String sessionId);
  Future<void> markSynced(int id);
  Future<void> markFailed(int id, String error);
  Future<void> markRejected(int id, String error, {int? currentRevision});
  Future<void> replaceSession(
    String ownerUid,
    String sessionId,
    List<Attendance> records, {
    int? expectedRevision,
  });
  Future<List<OutboxBatch>> allBatches(String ownerUid);
  Stream<List<OutboxBatch>> watchBatches(String ownerUid);
  Future<void> close();
}
