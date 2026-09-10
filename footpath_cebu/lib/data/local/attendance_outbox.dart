import 'dart:convert';
import 'dart:async';

import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:sqflite/sqflite.dart';

/// One queued "save this session's attendance" request. The whole batch is the
/// retry unit — attendance saves are wholesale-replace per session, so
/// re-sending the full batch is always safe.
class OutboxBatch {
  const OutboxBatch({
    required this.id,
    required this.ownerUid,
    required this.sessionId,
    required this.records,
    required this.retryCount,
    this.lastError,
    this.isRejected = false,
  });

  final int id;
  final String ownerUid;
  final String sessionId;
  final List<Attendance> records;
  final int retryCount;
  final String? lastError;
  final bool isRejected;
}

/// Durable queue of attendance saves that failed because the device was
/// offline. Backed by a single sqflite table so a queued roll call survives an
/// app restart. Pure persistence — retry timing and connectivity live in
/// [AttendanceSyncService].
class AttendanceOutbox {
  AttendanceOutbox({this._factory, this._dbPath});

  static const _table = 'outbox_attendance';

  /// Injected in tests (sqflite_common_ffi + in-memory path); null in the app,
  /// where the platform default factory and database directory are used.
  final DatabaseFactory? _factory;
  final String? _dbPath;

  Database? _db;
  final _changes = StreamController<void>.broadcast();

  Future<Database> _database() async {
    final existing = _db;
    if (existing != null && existing.isOpen) return existing;
    final factory = _factory ?? databaseFactory;
    final path =
        _dbPath ??
        '${await factory.getDatabasesPath()}/footpath_attendance_outbox.db';
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, version) => db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            owner_uid TEXT NOT NULL,
            session_id TEXT NOT NULL,
            records_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            retry_count INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            is_rejected INTEGER NOT NULL DEFAULT 0
          )
        '''),
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              "ALTER TABLE $_table ADD COLUMN owner_uid TEXT NOT NULL DEFAULT ''",
            );
            await db.delete(_table);
          }
          if (oldVersion < 3) {
            await db.execute(
              'ALTER TABLE $_table ADD COLUMN is_rejected INTEGER NOT NULL DEFAULT 0',
            );
          }
        },
      ),
    );
    _db = db;
    return db;
  }

  /// Queues a batch for later sync. Returns the new row id.
  Future<int> enqueue(
    String ownerUid,
    String sessionId,
    List<Attendance> records,
  ) async {
    final db = await _database();
    final id = await db.insert(_table, {
      'owner_uid': ownerUid,
      'session_id': sessionId,
      'records_json': jsonEncode(records.map((r) => r.toJson()).toList()),
      'created_at': DateTime.now().toIso8601String(),
      'retry_count': 0,
    });
    _notify();
    return id;
  }

  /// All queued batches, oldest first — the drain order. Sequential
  /// oldest-first drain means the newest save for a session wins on the
  /// server (last write wins, matching the endpoint's replace semantics).
  Future<List<OutboxBatch>> pendingBatches(String ownerUid) async {
    final db = await _database();
    final rows = await db.query(
      _table,
      where: 'owner_uid = ? AND is_rejected = 0',
      whereArgs: [ownerUid],
      orderBy: 'id ASC',
    );
    return rows.map(_toBatch).toList();
  }

  /// The most recently queued batch for one session, or null — the offline
  /// read fallback for the roll-call screen.
  Future<OutboxBatch?> latestBatchForSession(
    String ownerUid,
    String sessionId,
  ) async {
    final db = await _database();
    final rows = await db.query(
      _table,
      where: 'owner_uid = ? AND session_id = ?',
      whereArgs: [ownerUid, sessionId],
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _toBatch(rows.first);
  }

  /// The batch reached the server — drop it.
  Future<void> markSynced(int id) async {
    final db = await _database();
    await db.transaction((txn) async {
      final rows = await txn.query(_table, where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) return;
      final row = rows.single;
      // A successful newer full replacement resolves older rejected versions.
      await txn.delete(
        _table,
        where:
            'owner_uid = ? AND session_id = ? AND (id = ? OR (id < ? AND is_rejected = 1))',
        whereArgs: [row['owner_uid'], row['session_id'], id, id],
      );
    });
    _notify();
  }

  /// A sync attempt failed; keep the batch and record why.
  Future<void> markFailed(int id, String error) async {
    final db = await _database();
    await db.rawUpdate(
      'UPDATE $_table SET retry_count = retry_count + 1, last_error = ? '
      'WHERE id = ?',
      [error, id],
    );
    _notify();
  }

  Future<void> markRejected(int id, String error) async {
    final db = await _database();
    await db.rawUpdate(
      'UPDATE $_table SET is_rejected = 1, retry_count = retry_count + 1, last_error = ? WHERE id = ?',
      [error, id],
    );
    _notify();
  }

  /// The user explicitly saved a corrected complete snapshot. Replace all old
  /// versions atomically so a crash leaves either the old draft or the new one.
  Future<void> replaceSession(
    String ownerUid,
    String sessionId,
    List<Attendance> records,
  ) async {
    final db = await _database();
    await db.transaction((txn) async {
      await txn.delete(
        _table,
        where: 'owner_uid = ? AND session_id = ?',
        whereArgs: [ownerUid, sessionId],
      );
      await txn.insert(_table, {
        'owner_uid': ownerUid,
        'session_id': sessionId,
        'records_json': jsonEncode(records.map((r) => r.toJson()).toList()),
        'created_at': DateTime.now().toIso8601String(),
        'retry_count': 0,
      });
    });
    _notify();
  }

  Future<List<OutboxBatch>> allBatches(String ownerUid) async {
    final db = await _database();
    final rows = await db.query(
      _table,
      where: 'owner_uid = ?',
      whereArgs: [ownerUid],
      orderBy: 'id ASC',
    );
    return rows.map(_toBatch).toList();
  }

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

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> close() async {
    await _changes.close();
    await _db?.close();
    _db = null;
  }

  OutboxBatch _toBatch(Map<String, Object?> row) {
    final decoded = jsonDecode(row['records_json'] as String) as List;
    return OutboxBatch(
      id: row['id'] as int,
      ownerUid: row['owner_uid'] as String,
      sessionId: row['session_id'] as String,
      records: decoded
          .cast<Map<String, dynamic>>()
          .map(Attendance.fromJson)
          .toList(),
      retryCount: row['retry_count'] as int,
      lastError: row['last_error'] as String?,
      isRejected: row['is_rejected'] == 1,
    );
  }
}
