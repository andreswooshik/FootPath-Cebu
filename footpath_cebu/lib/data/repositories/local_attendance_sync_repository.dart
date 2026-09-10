import 'package:footpath_cebu/data/local/attendance_outbox.dart';
import 'package:footpath_cebu/data/local/attendance_write_queue.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/entities/attendance_sync_entry.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';
import 'package:footpath_cebu/domain/repositories/attendance_sync_repository.dart';

class LocalAttendanceSyncRepository implements AttendanceSyncRepository {
  LocalAttendanceSyncRepository({
    required this.outbox,
    required this.ownerUid,
    required this.requestSync,
    required this.writeQueue,
  });

  final AttendanceOutbox outbox;
  final String? Function() ownerUid;
  final Future<void> Function() requestSync;
  final AttendanceWriteQueue writeQueue;

  String _owner() {
    final owner = ownerUid();
    if (owner == null || owner.isEmpty) {
      throw AttendanceRepositoryException('Not signed in.');
    }
    return owner;
  }

  List<AttendanceSyncEntry> _entries(String owner, List<OutboxBatch> batches) {
    if (ownerUid() != owner) {
      throw AttendanceRepositoryException('The signed-in account changed.');
    }
    final latest = <String, OutboxBatch>{};
    for (final batch in batches) {
      latest[batch.sessionId] = batch;
    }
    return List.unmodifiable(
      latest.values.map(
        (batch) => AttendanceSyncEntry(
          sessionId: batch.sessionId,
          records: List.unmodifiable(batch.records),
          status: batch.isRejected
              ? AttendanceDeliveryStatus.needsCorrection
              : AttendanceDeliveryStatus.waitingToSync,
          error: batch.lastError,
          recoveryKey: '$owner:${batch.id}',
        ),
      ),
    );
  }

  @override
  Future<List<AttendanceSyncEntry>> fetchEntries() async {
    final owner = _owner();
    return _entries(owner, await outbox.allBatches(owner));
  }

  @override
  Stream<List<AttendanceSyncEntry>> watchEntries() {
    final owner = _owner();
    return outbox
        .watchBatches(owner)
        .map((batches) => _entries(owner, batches));
  }

  @override
  Future<void> syncNow() async {
    _owner();
    await requestSync();
  }

  @override
  Future<void> saveCorrection(
    AttendanceSyncEntry entry,
    List<Attendance> records,
  ) async {
    final owner = _owner();
    await writeQueue.run(() async {
      final latest = await outbox.latestBatchForSession(owner, entry.sessionId);
      if (ownerUid() != owner ||
          latest == null ||
          entry.recoveryKey != '$owner:${latest.id}') {
        throw AttendanceRepositoryException(
          'This saved draft has changed. Reopen Attendance sync before editing.',
        );
      }
      await outbox.replaceSession(
        owner,
        entry.sessionId,
        records,
        expectedRevision: latest.expectedRevision,
      );
    });
    if (ownerUid() != owner) {
      throw AttendanceRepositoryException('The signed-in account changed.');
    }
    try {
      await requestSync();
    } catch (_) {
      // The correction is already durable. A delivery-start failure leaves it
      // waiting; it must not be reported as a failed local save.
    }
  }
}

/// Web and mock repositories have no durable offline queue.
class OnlineAttendanceSyncRepository implements AttendanceSyncRepository {
  @override
  Future<void> saveCorrection(
    AttendanceSyncEntry entry,
    List<Attendance> records,
  ) async => throw AttendanceRepositoryException(
    'No offline attendance is stored on this platform.',
  );
  @override
  Future<List<AttendanceSyncEntry>> fetchEntries() async => const [];
  @override
  Stream<List<AttendanceSyncEntry>> watchEntries() => Stream.value(const []);
  @override
  Future<void> syncNow() async {}
}
