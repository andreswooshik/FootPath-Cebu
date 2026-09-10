import 'dart:async';

import 'package:footpath_cebu/data/local/attendance_outbox_store.dart';
import 'package:footpath_cebu/data/local/attendance_request_id.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:idb_shim/idb.dart';

class WebAttendanceOutbox implements AttendanceOutboxStore {
  WebAttendanceOutbox(this._factory, {String? databaseName})
    : _databaseName = databaseName ?? 'footpath_attendance_outbox';

  static const _storeName = 'attendance_batches';

  final IdbFactory _factory;
  final String _databaseName;
  final _changes = StreamController<void>.broadcast();
  Database? _db;

  Future<Database> _database() async => _db ??= await _factory.open(
    _databaseName,
    version: 1,
    onUpgradeNeeded: (event) {
      if (!event.database.objectStoreNames.contains(_storeName)) {
        event.database.createObjectStore(
          _storeName,
          keyPath: 'id',
          autoIncrement: true,
        );
      }
    },
  );

  @override
  Future<int> enqueue(
    String ownerUid,
    String sessionId,
    List<Attendance> records, {
    String? requestId,
    int? expectedRevision,
  }) async {
    final db = await _database();
    final transaction = db.transaction(_storeName, idbModeReadWrite);
    final key = await transaction
        .objectStore(_storeName)
        .add(
          _row(
            ownerUid,
            sessionId,
            records,
            requestId: requestId,
            expectedRevision: expectedRevision,
          ),
        );
    await transaction.completed;
    _notify();
    return key as int;
  }

  @override
  Future<List<OutboxBatch>> pendingBatches(String ownerUid) async =>
      (await allBatches(
        ownerUid,
      )).where((batch) => !batch.isRejected).toList(growable: false);

  @override
  Future<OutboxBatch?> latestBatchForSession(
    String ownerUid,
    String sessionId,
  ) async {
    final matches = (await allBatches(
      ownerUid,
    )).where((batch) => batch.sessionId == sessionId);
    return matches.isEmpty ? null : matches.last;
  }

  @override
  Future<void> markSynced(int id) async {
    final db = await _database();
    final transaction = db.transaction(_storeName, idbModeReadWrite);
    final store = transaction.objectStore(_storeName);
    final current = await store.getObject(id);
    if (current case final Map row) {
      final ownerUid = row['owner_uid'];
      final sessionId = row['session_id'];
      for (final candidate in await store.getAll()) {
        if (candidate case final Map candidateRow) {
          final candidateId = candidateRow['id'];
          if (candidateRow['owner_uid'] == ownerUid &&
              candidateRow['session_id'] == sessionId &&
              (candidateId == id ||
                  (candidateId is int &&
                      candidateId < id &&
                      candidateRow['is_rejected'] == true))) {
            await store.delete(candidateId);
          }
        }
      }
    }
    await transaction.completed;
    _notify();
  }

  @override
  Future<void> markFailed(int id, String error) => _update(id, (row) {
    row['retry_count'] = (row['retry_count'] as int? ?? 0) + 1;
    row['last_error'] = error;
  });

  @override
  Future<void> markRejected(int id, String error, {int? currentRevision}) =>
      _update(id, (row) {
        row['is_rejected'] = true;
        row['retry_count'] = (row['retry_count'] as int? ?? 0) + 1;
        row['last_error'] = error;
        if (currentRevision != null) {
          row['expected_revision'] = currentRevision;
        }
      });

  @override
  Future<void> replaceSession(
    String ownerUid,
    String sessionId,
    List<Attendance> records, {
    int? expectedRevision,
  }) async {
    final db = await _database();
    final transaction = db.transaction(_storeName, idbModeReadWrite);
    final store = transaction.objectStore(_storeName);
    for (final candidate in await store.getAll()) {
      if (candidate case final Map row) {
        if (row['owner_uid'] == ownerUid && row['session_id'] == sessionId) {
          await store.delete(row['id']);
        }
      }
    }
    await store.add(
      _row(ownerUid, sessionId, records, expectedRevision: expectedRevision),
    );
    await transaction.completed;
    _notify();
  }

  @override
  Future<List<OutboxBatch>> allBatches(String ownerUid) async {
    final db = await _database();
    final transaction = db.transaction(_storeName, idbModeReadOnly);
    final values = await transaction.objectStore(_storeName).getAll();
    await transaction.completed;
    final batches =
        values
            .whereType<Map>()
            .where((row) => row['owner_uid'] == ownerUid)
            .map(_toBatch)
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    return batches;
  }

  @override
  Stream<List<OutboxBatch>> watchBatches(String ownerUid) =>
      Stream.multi((controller) {
        var cancelled = false;
        Future<void> tail = Future.value();
        void refresh() {
          tail = tail.then((_) async {
            if (cancelled) return;
            try {
              final rows = await allBatches(ownerUid);
              if (!cancelled) controller.add(rows);
            } catch (error, stack) {
              if (!cancelled) controller.addError(error, stack);
            }
          });
        }

        final subscription = _changes.stream.listen(
          (_) => refresh(),
          onDone: controller.close,
        );
        controller.onCancel = () {
          cancelled = true;
          return subscription.cancel();
        };
        refresh();
      });

  Future<void> _update(
    int id,
    void Function(Map<String, Object?>) change,
  ) async {
    final db = await _database();
    final transaction = db.transaction(_storeName, idbModeReadWrite);
    final store = transaction.objectStore(_storeName);
    final value = await store.getObject(id);
    if (value case final Map raw) {
      final row = Map<String, Object?>.from(raw);
      change(row);
      await store.put(row);
    }
    await transaction.completed;
    _notify();
  }

  Map<String, Object?> _row(
    String ownerUid,
    String sessionId,
    List<Attendance> records, {
    String? requestId,
    int? expectedRevision,
  }) => {
    'owner_uid': ownerUid,
    'session_id': sessionId,
    'records': records.map((record) => record.toJson()).toList(),
    'created_at': DateTime.now().toIso8601String(),
    'retry_count': 0,
    'last_error': null,
    'is_rejected': false,
    'request_id': requestId ?? AttendanceRequestId.create(),
    'expected_revision': expectedRevision,
  };

  OutboxBatch _toBatch(Map row) => OutboxBatch(
    id: row['id'] as int,
    ownerUid: row['owner_uid'] as String,
    sessionId: row['session_id'] as String,
    records: (row['records'] as List)
        .map(
          (value) =>
              Attendance.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList(growable: false),
    retryCount: row['retry_count'] as int? ?? 0,
    requestId: row['request_id'] as String,
    expectedRevision: row['expected_revision'] as int?,
    lastError: row['last_error'] as String?,
    isRejected: row['is_rejected'] as bool? ?? false,
  );

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<void> close() async {
    await _changes.close();
    _db?.close();
    _db = null;
  }
}
