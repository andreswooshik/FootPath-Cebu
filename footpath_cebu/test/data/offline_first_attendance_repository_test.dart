import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/data/local/attendance_outbox.dart';
import 'package:footpath_cebu/data/local/attendance_sync_service.dart';
import 'package:footpath_cebu/data/repositories/offline_first_attendance_repository.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Scriptable stand-in for the live API repository: each call either throws
/// the queued error or records/returns normally.
class _FakeApiRepository implements AttendanceRepository {
  Exception? saveError;
  Exception? fetchSessionError;
  int saveCalls = 0;
  final List<(String, List<Attendance>)> savedBatches = [];
  List<Attendance> sessionRecords = const [];

  @override
  Future<List<Attendance>> saveSessionAttendance(
    String sessionId,
    List<Attendance> records,
  ) async {
    saveCalls++;
    final error = saveError;
    if (error != null) throw error;
    savedBatches.add((sessionId, records));
    return records;
  }

  @override
  Future<List<Attendance>> fetchAttendanceForSession(String sessionId) async {
    final error = fetchSessionError;
    if (error != null) throw error;
    return sessionRecords;
  }

  @override
  Future<List<Attendance>> fetchAttendanceForPlayer(
    String playerId, {
    String? unlockToken,
  }) async {
    return sessionRecords;
  }
}

Attendance _record(String playerId) => Attendance(
  playerId: playerId,
  status: AttendanceStatus.present,
  updatedAt: DateTime(2026, 7, 17, 16, 30),
  sessionId: 's1',
  effort: 70,
);

void main() {
  setUpAll(sqfliteFfiInit);

  late _FakeApiRepository inner;
  late AttendanceOutbox outbox;
  late OfflineFirstAttendanceRepository repo;
  const ownerUid = 'coach-a';

  setUp(() {
    inner = _FakeApiRepository();
    outbox = AttendanceOutbox(
      factory: databaseFactoryFfi,
      dbPath: inMemoryDatabasePath,
    );
    addTearDown(outbox.close);
    repo = OfflineFirstAttendanceRepository(
      inner: inner,
      outbox: outbox,
      ownerUid: () => ownerUid,
    );
  });

  group('saveSessionAttendance', () {
    test('online: passes through and queues nothing', () async {
      final records = [_record('p1')];
      final saved = await repo.saveSessionAttendance('s1', records);
      expect(saved, records);
      expect(inner.savedBatches, hasLength(1));
      expect(await outbox.pendingBatches(ownerUid), isEmpty);
    });

    test(
      'network failure: queues the batch and returns optimistically',
      () async {
        inner.saveError = AttendanceNetworkException('offline');
        final records = [_record('p1'), _record('p2')];

        final saved = await repo.saveSessionAttendance('s1', records);

        expect(saved, records); // the screen still reports success
        final pending = await outbox.pendingBatches(ownerUid);
        expect(pending, hasLength(1));
        expect(pending.single.sessionId, 's1');
        expect(pending.single.records, hasLength(2));
      },
    );

    test('validation failure: propagates and does NOT queue', () async {
      inner.saveError = AttendanceRepositoryException('Request failed (400).');

      await expectLater(
        repo.saveSessionAttendance('s1', [_record('p1')]),
        throwsA(isA<AttendanceRepositoryException>()),
      );
      expect(await outbox.pendingBatches(ownerUid), isEmpty);
    });
  });

  group('fetchAttendanceForSession', () {
    test('failure falls back to the latest queued batch', () async {
      inner.saveError = AttendanceNetworkException('offline');
      await repo.saveSessionAttendance('s1', [_record('p1')]);

      inner.fetchSessionError = AttendanceNetworkException('offline');
      final records = await repo.fetchAttendanceForSession('s1');
      expect(records.single.playerId, 'p1');
    });

    test('failure with nothing queued rethrows', () async {
      inner.fetchSessionError = AttendanceNetworkException('offline');
      await expectLater(
        repo.fetchAttendanceForSession('s1'),
        throwsA(isA<AttendanceNetworkException>()),
      );
    });
  });

  group('AttendanceSyncService.drain', () {
    test('replays queued batches in order and clears the outbox', () async {
      await outbox.enqueue(ownerUid, 's1', [_record('p1')]);
      await outbox.enqueue(ownerUid, 's2', [_record('p2')]);

      final service = AttendanceSyncService(
        outbox: outbox,
        inner: inner,
        ownerUid: () => ownerUid,
      );
      addTearDown(service.dispose);
      await service.drain();

      expect(inner.savedBatches.map((b) => b.$1), ['s1', 's2']);
      expect(await outbox.pendingBatches(ownerUid), isEmpty);
    });

    test('a network failure stops the drain and keeps the batch', () async {
      await outbox.enqueue(ownerUid, 's1', [_record('p1')]);
      inner.saveError = AttendanceNetworkException('still offline');

      final service = AttendanceSyncService(
        outbox: outbox,
        inner: inner,
        ownerUid: () => ownerUid,
      );
      addTearDown(service.dispose);
      await service.drain();

      final pending = await outbox.pendingBatches(ownerUid);
      expect(pending, hasLength(1));
      expect(pending.single.retryCount, 1);
      expect(pending.single.lastError, 'still offline');
    });

    test(
      'a validation rejection drops the batch instead of retrying forever',
      () async {
        await outbox.enqueue(ownerUid, 's1', [_record('p1')]);
        inner.saveError = AttendanceRepositoryException(
          'Request failed (400).',
        );

        final service = AttendanceSyncService(
          outbox: outbox,
          inner: inner,
          ownerUid: () => ownerUid,
        );
        addTearDown(service.dispose);
        await service.drain();

        expect(await outbox.pendingBatches(ownerUid), isEmpty);
      },
    );
  });
}
