import 'dart:convert';

import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:sqflite/sqflite.dart';

/// One queued "save this session's attendance" request. The whole batch is the
/// retry unit — attendance saves are wholesale-replace per session, so
/// re-sending the full batch is always safe.
class OutboxBatch {
  const OutboxBatch({
    required this.id,
    required this.sessionId,
    required this.records,
    required this.retryCount,
    this.lastError,
  });

  final int id;
  final String sessionId;
  final List<Attendance> records;
  final int retryCount;
  final String? lastError;
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

  Future<Database> _database() async {
    final existing = _db;
    if (existing != null && existing.isOpen) return existing;
    final factory = _factory ?? databaseFactory;
    final path = _dbPath ??
        '${await factory.getDatabasesPath()}/footpath_attendance_outbox.db';
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) => db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            records_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            retry_count INTEGER NOT NULL DEFAULT 0,
            last_error TEXT
          )
        '''),
      ),
    );
    _db = db;
    return db;
  }

  /// Queues a batch for later sync. Returns the new row id.
  Future<int> enqueue(String sessionId, List<Attendance> records) async {
    final db = await _database();
    return db.insert(_table, {
      'session_id': sessionId,
      'records_json': jsonEncode(records.map((r) => r.toJson()).toList()),
      'created_at': DateTime.now().toIso8601String(),
      'retry_count': 0,
    });
  }

  /// All queued batches, oldest first — the drain order. Sequential
  /// oldest-first drain means the newest save for a session wins on the
  /// server (last write wins, matching the endpoint's replace semantics).
  Future<List<OutboxBatch>> pendingBatches() async {
    final db = await _database();
    final rows = await db.query(_table, orderBy: 'id ASC');
    return rows.map(_toBatch).toList();
  }

  /// The most recently queued batch for one session, or null — the offline
  /// read fallback for the roll-call screen.
  Future<OutboxBatch?> latestBatchForSession(String sessionId) async {
    final db = await _database();
    final rows = await db.query(
      _table,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _toBatch(rows.first);
  }

  /// The batch reached the server — drop it.
  Future<void> markSynced(int id) async {
    final db = await _database();
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  /// A sync attempt failed; keep the batch and record why.
  Future<void> markFailed(int id, String error) async {
    final db = await _database();
    await db.rawUpdate(
      'UPDATE $_table SET retry_count = retry_count + 1, last_error = ? '
      'WHERE id = ?',
      [error, id],
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  OutboxBatch _toBatch(Map<String, Object?> row) {
    final decoded = jsonDecode(row['records_json'] as String) as List;
    return OutboxBatch(
      id: row['id'] as int,
      sessionId: row['session_id'] as String,
      records: decoded
          .cast<Map<String, dynamic>>()
          .map(Attendance.fromJson)
          .toList(),
      retryCount: row['retry_count'] as int,
      lastError: row['last_error'] as String?,
    );
  }
}
