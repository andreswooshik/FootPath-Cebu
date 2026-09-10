import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/data/local/attendance_outbox.dart';
import 'package:footpath_cebu/data/local/attendance_sync_service.dart';
import 'package:footpath_cebu/data/local/attendance_write_queue.dart';
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
  Future<void> Function()? onSave;
  final List<(String, List<Attendance>)> savedBatches = [];
  List<Attendance> sessionRecords = const [];

  @override
  Future<List<Attendance>> saveSessionAttendance(
    String sessionId,
    List<Attendance> records,
  ) async {
    saveCalls++;
    await onSave?.call();
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
    test(
      'an account switch during a failed save cannot queue work for the new account',
      () async {
        var activeUid = ownerUid;
        final started = Completer<void>();
        final finish = Completer<void>();
        inner.onSave = () {
          started.complete();
          return finish.future;
        };
        inner.saveError = AttendanceNetworkException('offline');
        final repository = OfflineFirstAttendanceRepository(
          inner: inner,
          outbox: outbox,
          ownerUid: () => activeUid,
        );
        final result = repository.saveSessionAttendance('s1', [_record('p1')]);
        final assertion = expectLater(
          result,
          throwsA(isA<AttendanceRepositoryException>()),
        );
        await started.future;
        activeUid = 'coach-b';
        finish.complete();
        await assertion;
        expect(await outbox.pendingBatches(ownerUid), isEmpty);
        expect(await outbox.pendingBatches('coach-b'), isEmpty);
      },
    );

    test('a newer save joins existing queued work and replays last', () async {
      await outbox.enqueue(ownerUid, 's1', [_record('old')]);
      final queue = AttendanceWriteQueue();
      final repository = OfflineFirstAttendanceRepository(
        inner: inner,
        outbox: outbox,
        ownerUid: () => ownerUid,
        writeQueue: queue,
      );
      await repository.saveSessionAttendance('s1', [_record('new')]);
      expect(inner.saveCalls, 0);
      final service = AttendanceSyncService(
        outbox: outbox,
        inner: inner,
        ownerUid: () => ownerUid,
        writeQueue: queue,
      );
      addTearDown(service.dispose);
      await service.drain();
      expect(inner.savedBatches.map((batch) => batch.$2.single.playerId), [
        'old',
        'new',
      ]);
      expect(await outbox.pendingBatches(ownerUid), isEmpty);
    });

    test(
      'foreground save waits for replay before writing newer marks',
      () async {
        await outbox.enqueue(ownerUid, 's1', [_record('old')]);
        final queue = AttendanceWriteQueue();
        final started = Completer<void>();
        final finish = Completer<void>();
        inner.onSave = () async {
          if (inner.saveCalls == 1) {
            started.complete();
            await finish.future;
          }
        };
        final service = AttendanceSyncService(
          outbox: outbox,
          inner: inner,
          ownerUid: () => ownerUid,
          writeQueue: queue,
        );
        addTearDown(service.dispose);
        final repository = OfflineFirstAttendanceRepository(
          inner: inner,
          outbox: outbox,
          ownerUid: () => ownerUid,
          writeQueue: queue,
        );
        final drain = service.drain();
        await started.future;
        final save = repository.saveSessionAttendance('s1', [_record('new')]);
        expect(inner.saveCalls, 1);
        finish.complete();
        await drain;
        await save;
        expect(inner.savedBatches.map((batch) => batch.$2.single.playerId), [
          'old',
          'new',
        ]);
      },
    );
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
      inner.saveError = AttendanceRepositoryException(
        'Request failed (400).',
        statusCode: 400,
      );

      await expectLater(
        repo.saveSessionAttendance('s1', [_record('p1')]),
        throwsA(isA<AttendanceRepositoryException>()),
      );
      expect(await outbox.pendingBatches(ownerUid), isEmpty);
    });
  });

  group('fetchAttendanceForSession', () {
    test(
      'keeps newer queued marks visible after an authorized online read',
      () async {
        inner.sessionRecords = [_record('old')];
        await outbox.enqueue(ownerUid, 's1', [_record('new')]);
        expect(
          (await repo.fetchAttendanceForSession('s1')).single.playerId,
          'new',
        );
      },
    );
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

    test('an HTTP error never falls back to queued attendance', () async {
      inner.saveError = AttendanceNetworkException('offline');
      await repo.saveSessionAttendance('s1', [_record('p1')]);

      inner.fetchSessionError = AttendanceRepositoryException(
        'Request failed (403).',
        statusCode: 403,
      );
      await expectLater(
        repo.fetchAttendanceForSession('s1'),
        throwsA(
          isA<AttendanceRepositoryException>().having(
            (error) => error.message,
            'message',
            'Request failed (403).',
          ),
        ),
      );
    });
  });

  group('AttendanceSyncService.drain', () {
    for (final dispose in [false, true]) {
      test(
        'stops replay between batches after ${dispose ? 'disposal' : 'account switch'}',
        () async {
          var activeUid = ownerUid;
          await outbox.enqueue(ownerUid, 's1', [_record('p1')]);
          await outbox.enqueue(ownerUid, 's2', [_record('p2')]);
          final service = AttendanceSyncService(
            outbox: outbox,
            inner: inner,
            ownerUid: () => activeUid,
          );
          addTearDown(service.dispose);
          inner.onSave = () async {
            if (dispose) {
              service.dispose();
            } else {
              activeUid = 'coach-b';
            }
          };
          await service.drain();
          expect(inner.saveCalls, 1);
          expect(
            (await outbox.pendingBatches(ownerUid)).single.sessionId,
            's2',
          );
        },
      );
    }
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
      'a validation rejection retains the batch and pauses automatic retry',
      () async {
        await outbox.enqueue(ownerUid, 's1', [_record('p1')]);
        inner.saveError = AttendanceRepositoryException(
          'Request failed (400).',
          statusCode: 400,
        );

        final service = AttendanceSyncService(
          outbox: outbox,
          inner: inner,
          ownerUid: () => ownerUid,
        );
        addTearDown(service.dispose);
        await service.drain();

        expect(await outbox.pendingBatches(ownerUid), isEmpty);
        final rejected = (await outbox.allBatches(ownerUid)).single;
        expect(rejected.isRejected, isTrue);
        expect(rejected.records.single.playerId, 'p1');
        expect(rejected.lastError, 'Request failed (400).');
        await service.drain();
        expect(inner.saveCalls, 1);
      },
    );

    for (final status in [401, 403, 408, 429, 500, 503]) {
      test('HTTP $status keeps the queued batch for a later retry', () async {
        await outbox.enqueue(ownerUid, 's1', [_record('p1')]);
        inner.saveError = AttendanceRepositoryException(
          'Request failed ($status).',
          statusCode: status,
        );

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
        expect(pending.single.lastError, 'Request failed ($status).');
      });
    }

    test(
      'an unknown repository error is retained to avoid data loss',
      () async {
        await outbox.enqueue(ownerUid, 's1', [_record('p1')]);
        inner.saveError = AttendanceRepositoryException('Unexpected failure.');

        final service = AttendanceSyncService(
          outbox: outbox,
          inner: inner,
          ownerUid: () => ownerUid,
        );
        addTearDown(service.dispose);
        await service.drain();

        expect(await outbox.pendingBatches(ownerUid), hasLength(1));
      },
    );
  });
}
