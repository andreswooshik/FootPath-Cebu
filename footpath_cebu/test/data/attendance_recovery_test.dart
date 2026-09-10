import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/data/local/attendance_outbox.dart';
import 'package:footpath_cebu/data/local/attendance_sync_service.dart';
import 'package:footpath_cebu/data/local/attendance_write_queue.dart';
import 'package:footpath_cebu/data/repositories/local_attendance_sync_repository.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/entities/attendance_sync_entry.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Attendance record(String player, {String note = 'Original note'}) => Attendance(
  playerId: player,
  sessionId: 's1',
  sessionName: 'Training',
  status: AttendanceStatus.present,
  updatedAt: DateTime(2026, 9, 10),
  effort: 80,
  performanceScore: 8,
  note: note,
);

class _Writer implements SessionAttendanceWriter {
  final saved = <String>[];
  bool reject = true;
  @override
  Future<List<Attendance>> saveSessionAttendance(
    String sessionId,
    List<Attendance> records,
  ) async {
    if (reject && sessionId == 's1') {
      throw AttendanceRepositoryException(
        'Correct the player selection.',
        statusCode: 422,
      );
    }
    saved.add(sessionId);
    return records;
  }
}

class _VersionedWriter
    implements SessionAttendanceWriter, VersionedSessionAttendanceWriter {
  final calls = <({String requestId, int? expectedRevision})>[];
  AttendanceRepositoryException? error;

  @override
  int? revisionForSession(String sessionId) => 0;

  @override
  Future<List<Attendance>> saveSessionAttendance(
    String sessionId,
    List<Attendance> records,
  ) => throw UnimplementedError();

  @override
  Future<List<Attendance>> saveVersionedSessionAttendance(
    String sessionId,
    List<Attendance> records, {
    required String requestId,
    int? expectedRevision,
  }) async {
    calls.add((requestId: requestId, expectedRevision: expectedRevision));
    if (error case final failure?) throw failure;
    return records;
  }
}

void main() {
  setUpAll(sqfliteFfiInit);
  late AttendanceOutbox outbox;
  late _Writer writer;
  late AttendanceSyncService service;
  late LocalAttendanceSyncRepository repository;
  late String owner;
  setUp(() {
    owner = 'coach-a';
    outbox = AttendanceOutbox(
      factory: databaseFactoryFfi,
      dbPath: inMemoryDatabasePath,
    );
    final queue = AttendanceWriteQueue();
    writer = _Writer();
    service = AttendanceSyncService(
      outbox: outbox,
      inner: writer,
      ownerUid: () => owner,
      writeQueue: queue,
    );
    repository = LocalAttendanceSyncRepository(
      outbox: outbox,
      ownerUid: () => owner,
      requestSync: service.drain,
      writeQueue: queue,
    );
  });
  tearDown(() async {
    service.dispose();
    await outbox.close();
  });

  test(
    'rejection retains complete records and does not block other sessions',
    () async {
      await outbox.enqueue(owner, 's1', [record('p1')]);
      await outbox.enqueue(owner, 's2', [record('p2')]);
      await service.drain();
      expect(writer.saved, ['s2']);
      final entry = (await repository.fetchEntries()).single;
      expect(entry.status, AttendanceDeliveryStatus.needsCorrection);
      expect(entry.error, 'Correct the player selection.');
      expect(entry.records.single.note, 'Original note');
      expect(entry.records.single.performanceScore, 8);
    },
  );

  test(
    'replay preserves the queued request id and expected revision',
    () async {
      final versioned = _VersionedWriter();
      final versionedService = AttendanceSyncService(
        outbox: outbox,
        inner: versioned,
        ownerUid: () => owner,
      );
      addTearDown(versionedService.dispose);
      await outbox.enqueue(
        owner,
        's1',
        [record('p1')],
        requestId: 'request-1234567890',
        expectedRevision: 7,
      );

      await versionedService.drain();

      expect(versioned.calls.single.requestId, 'request-1234567890');
      expect(versioned.calls.single.expectedRevision, 7);
      expect(await outbox.pendingBatches(owner), isEmpty);
    },
  );

  test(
    'revision conflict retains every later draft for manual recovery',
    () async {
      final versioned = _VersionedWriter()
        ..error = AttendanceRepositoryException(
          'Reload attendance.',
          statusCode: 409,
          code: 'ATTENDANCE_REVISION_CONFLICT',
          details: {'currentRevision': 9},
        );
      final versionedService = AttendanceSyncService(
        outbox: outbox,
        inner: versioned,
        ownerUid: () => owner,
      );
      addTearDown(versionedService.dispose);
      await outbox.enqueue(owner, 's1', [record('p1')], expectedRevision: 7);
      await outbox.enqueue(owner, 's1', [record('p2')], expectedRevision: 8);

      await versionedService.drain();

      expect(versioned.calls, hasLength(1));
      final retained = await outbox.allBatches(owner);
      expect(retained, hasLength(2));
      expect(retained.every((batch) => batch.isRejected), isTrue);
      expect(retained.every((batch) => batch.expectedRevision == 9), isTrue);
    },
  );

  test(
    'saved correction replaces rejected versions and retries successfully',
    () async {
      await outbox.enqueue(owner, 's1', [record('old')]);
      await service.drain();
      final entry = (await repository.fetchEntries()).single;
      writer.reject = false;
      await repository.saveCorrection(entry, [record('corrected')]);
      expect(await repository.fetchEntries(), isEmpty);
      expect(writer.saved, ['s1']);
    },
  );

  test('a rejected correction retains the newly edited values', () async {
    await outbox.enqueue(owner, 's1', [record('old')]);
    await service.drain();
    final entry = (await repository.fetchEntries()).single;
    await repository.saveCorrection(entry, [
      record('new', note: 'Corrected note'),
    ]);
    final retained = (await repository.fetchEntries()).single;
    expect(retained.records.single.note, 'Corrected note');
    expect(retained.status, AttendanceDeliveryStatus.needsCorrection);
    expect(retained.recoveryKey, isNot(entry.recoveryKey));
  });

  test('a stale correction cannot overwrite a newer local draft', () async {
    await outbox.enqueue(owner, 's1', [record('old')]);
    final entry = (await repository.fetchEntries()).single;
    await outbox.enqueue(owner, 's1', [record('new')]);
    await expectLater(
      repository.saveCorrection(entry, [record('stale')]),
      throwsA(isA<AttendanceRepositoryException>()),
    );
    expect(
      (await repository.fetchEntries()).single.records.single.playerId,
      'new',
    );
  });

  test('an account change cannot recover another account draft', () async {
    await outbox.enqueue(owner, 's1', [record('a')]);
    final entry = (await repository.fetchEntries()).single;
    owner = 'coach-b';
    await outbox.enqueue(owner, 's1', [record('b')]);
    await expectLater(
      repository.saveCorrection(entry, [record('wrong-owner')]),
      throwsA(isA<AttendanceRepositoryException>()),
    );
    expect(
      (await repository.fetchEntries()).single.records.single.playerId,
      'b',
    );
    expect(
      (await outbox.allBatches('coach-a')).single.records.single.playerId,
      'a',
    );
  });

  test(
    'newer accepted replacement clears older rejection for that session only',
    () async {
      final rejected = await outbox.enqueue(owner, 's1', [record('old')]);
      await outbox.markRejected(rejected, 'invalid');
      final other = await outbox.enqueue('coach-b', 's1', [record('other')]);
      await outbox.markRejected(other, 'invalid');
      await outbox.enqueue(owner, 's1', [record('new')]);
      writer.reject = false;
      await service.drain();
      expect(await outbox.allBatches(owner), isEmpty);
      expect(await outbox.allBatches('coach-b'), hasLength(1));
    },
  );

  test(
    'status stream updates after queue, rejection, and accepted delivery',
    () async {
      final events = StreamIterator(repository.watchEntries());
      addTearDown(events.cancel);
      await events.moveNext();
      expect(events.current, isEmpty);
      await outbox.enqueue(owner, 's1', [record('p1')]);
      await events.moveNext();
      expect(
        events.current.single.status,
        AttendanceDeliveryStatus.waitingToSync,
      );
      await service.drain();
      await events.moveNext();
      expect(
        events.current.single.status,
        AttendanceDeliveryStatus.needsCorrection,
      );
      final entry = events.current.single;
      writer.reject = false;
      await repository.saveCorrection(entry, [record('fixed')]);
      while (await events.moveNext()) {
        if (events.current.isEmpty) break;
      }
      expect(events.current, isEmpty);
    },
  );

  test('rejected records survive closing and reopening the database', () async {
    final directory = await Directory.systemTemp.createTemp(
      'attendance-recovery-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/attendance.db';
    final first = AttendanceOutbox(factory: databaseFactoryFfi, dbPath: path);
    final id = await first.enqueue('coach-a', 's1', [record('p1')]);
    await first.markRejected(id, 'Session is closed.');
    await first.close();
    final reopened = AttendanceOutbox(
      factory: databaseFactoryFfi,
      dbPath: path,
    );
    final retained = (await reopened.allBatches('coach-a')).single;
    expect(retained.isRejected, isTrue);
    expect(retained.records.single.note, 'Original note');
    expect(retained.lastError, 'Session is closed.');
    await reopened.close();
  });

  test('v2 database upgrade preserves existing queued work', () async {
    final directory = await Directory.systemTemp.createTemp(
      'attendance-upgrade-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/attendance.db';
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) => db.execute(
          'CREATE TABLE outbox_attendance (id INTEGER PRIMARY KEY AUTOINCREMENT, owner_uid TEXT NOT NULL, session_id TEXT NOT NULL, records_json TEXT NOT NULL, created_at TEXT NOT NULL, retry_count INTEGER NOT NULL DEFAULT 0, last_error TEXT)',
        ),
      ),
    );
    await db.insert('outbox_attendance', {
      'owner_uid': 'coach-a',
      'session_id': 's1',
      'records_json':
          '[{"playerId":"p1","status":"PRESENT","updatedAt":"2026-09-10T00:00:00"}]',
      'created_at': '2026-09-10',
    });
    await db.close();
    final upgraded = AttendanceOutbox(
      factory: databaseFactoryFfi,
      dbPath: path,
    );
    final batch = (await upgraded.pendingBatches('coach-a')).single;
    expect(batch.isRejected, isFalse);
    await upgraded.markRejected(batch.id, 'Retained after migration');
    expect((await upgraded.allBatches('coach-a')).single.isRejected, isTrue);
    await upgraded.close();
  });
}
