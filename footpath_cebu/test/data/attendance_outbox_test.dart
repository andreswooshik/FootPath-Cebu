import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/data/local/attendance_outbox.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Attendance _record(String playerId, {AttendanceStatus? status}) => Attendance(
      playerId: playerId,
      status: status ?? AttendanceStatus.present,
      updatedAt: DateTime(2026, 7, 17, 16, 30),
      sessionId: 's1',
      effort: 85,
      note: 'Sharp today.',
    );

void main() {
  setUpAll(sqfliteFfiInit);

  AttendanceOutbox newOutbox() => AttendanceOutbox(
        factory: databaseFactoryFfi,
        dbPath: inMemoryDatabasePath,
      );

  test('enqueue round-trips the batch through pendingBatches', () async {
    final outbox = newOutbox();
    addTearDown(outbox.close);

    await outbox.enqueue('s1', [_record('p1'), _record('p2')]);

    final pending = await outbox.pendingBatches();
    expect(pending, hasLength(1));
    final batch = pending.single;
    expect(batch.sessionId, 's1');
    expect(batch.retryCount, 0);
    expect(batch.lastError, isNull);
    expect(batch.records.map((r) => r.playerId), ['p1', 'p2']);
    expect(batch.records.first.status, AttendanceStatus.present);
    expect(batch.records.first.effort, 85);
    expect(batch.records.first.note, 'Sharp today.');
  });

  test('batches drain oldest first and markSynced removes them', () async {
    final outbox = newOutbox();
    addTearDown(outbox.close);

    final first = await outbox.enqueue('s1', [_record('p1')]);
    final second = await outbox.enqueue('s2', [_record('p2')]);

    var pending = await outbox.pendingBatches();
    expect(pending.map((b) => b.id), [first, second]);

    await outbox.markSynced(first);
    pending = await outbox.pendingBatches();
    expect(pending.map((b) => b.id), [second]);
  });

  test('markFailed keeps the batch, counts retries, records the error',
      () async {
    final outbox = newOutbox();
    addTearDown(outbox.close);

    final id = await outbox.enqueue('s1', [_record('p1')]);
    await outbox.markFailed(id, 'offline');
    await outbox.markFailed(id, 'still offline');

    final batch = (await outbox.pendingBatches()).single;
    expect(batch.retryCount, 2);
    expect(batch.lastError, 'still offline');
  });

  test('latestBatchForSession returns the newest batch for that session only',
      () async {
    final outbox = newOutbox();
    addTearDown(outbox.close);

    await outbox.enqueue('s1', [_record('p1')]);
    await outbox.enqueue('s2', [_record('p2')]);
    await outbox.enqueue(
      's1',
      [_record('p1', status: AttendanceStatus.excused)],
    );

    final latest = await outbox.latestBatchForSession('s1');
    expect(latest, isNotNull);
    expect(latest!.records.single.status, AttendanceStatus.excused);

    expect(await outbox.latestBatchForSession('missing'), isNull);
  });
}
