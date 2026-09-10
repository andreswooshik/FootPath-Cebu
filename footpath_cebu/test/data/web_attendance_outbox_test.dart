import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/data/local/web_attendance_outbox.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:idb_shim/idb_client_memory.dart';

Attendance _record(String playerId) => Attendance(
  playerId: playerId,
  sessionId: 's1',
  status: AttendanceStatus.present,
  updatedAt: DateTime(2026, 9, 11),
  note: 'Retained in IndexedDB',
);

void main() {
  late String databaseName;

  setUp(() async {
    databaseName = 'attendance-outbox-${DateTime.now().microsecondsSinceEpoch}';
    await idbFactoryMemory.deleteDatabase(databaseName);
  });

  tearDown(() => idbFactoryMemory.deleteDatabase(databaseName));

  test(
    'IndexedDB outbox persists delivery metadata and account scope',
    () async {
      final outbox = WebAttendanceOutbox(
        idbFactoryMemory,
        databaseName: databaseName,
      );
      await outbox.enqueue(
        'coach-a',
        's1',
        [_record('p1')],
        requestId: 'request-1234567890',
        expectedRevision: 4,
      );
      await outbox.enqueue('coach-b', 's1', [_record('p2')]);

      final batch = (await outbox.pendingBatches('coach-a')).single;
      expect(batch.requestId, 'request-1234567890');
      expect(batch.expectedRevision, 4);
      expect(batch.records.single.note, 'Retained in IndexedDB');
      expect(batch.records.single.playerId, 'p1');
      await outbox.close();

      final reopened = WebAttendanceOutbox(
        idbFactoryMemory,
        databaseName: databaseName,
      );
      expect(await reopened.pendingBatches('coach-a'), hasLength(1));
      expect(await reopened.pendingBatches('coach-b'), hasLength(1));
      await reopened.close();
    },
  );

  test('IndexedDB outbox supports rejection correction and cleanup', () async {
    final outbox = WebAttendanceOutbox(
      idbFactoryMemory,
      databaseName: databaseName,
    );
    final rejected = await outbox.enqueue('coach-a', 's1', [
      _record('old'),
    ], expectedRevision: 2);
    await outbox.markRejected(
      rejected,
      'Attendance changed.',
      currentRevision: 5,
    );
    final retained = (await outbox.allBatches('coach-a')).single;
    expect(retained.isRejected, isTrue);
    expect(retained.expectedRevision, 5);

    await outbox.replaceSession('coach-a', 's1', [
      _record('corrected'),
    ], expectedRevision: retained.expectedRevision);
    final correction = (await outbox.pendingBatches('coach-a')).single;
    expect(correction.records.single.playerId, 'corrected');
    expect(correction.expectedRevision, 5);
    await outbox.markSynced(correction.id);
    expect(await outbox.allBatches('coach-a'), isEmpty);
    await outbox.close();
  });
}
