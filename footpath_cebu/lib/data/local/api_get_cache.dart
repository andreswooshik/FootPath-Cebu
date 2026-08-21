import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// A successful JSON GET response stored for one authenticated Firebase user.
///
/// The owner UID is part of the primary key. A cached response written while
/// one account is active can therefore never be returned to another account on
/// the same device.
class CachedApiGet {
  const CachedApiGet({
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

/// Durable, owner-scoped cache for successful authenticated JSON GETs.
///
/// Network policy deliberately does not live here. [AuthenticatedApiClient]
/// decides when a cached value is safe to use; this class only persists and
/// retrieves values for an explicit owner and request key.
class ApiGetCache {
  ApiGetCache({
    this.databaseFactoryOverride,
    this.databasePath,
    this.maxAge = const Duration(hours: 24),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static final ApiGetCache shared = ApiGetCache();

  static const _table = 'api_get_cache';

  final DatabaseFactory? databaseFactoryOverride;
  final String? databasePath;
  final Duration maxAge;
  final DateTime Function() _now;

  Database? _databaseInstance;

  Future<Database> _database() async {
    final existing = _databaseInstance;
    if (existing != null && existing.isOpen) return existing;

    final factory = databaseFactoryOverride ?? databaseFactory;
    final path =
        databasePath ??
        '${await factory.getDatabasesPath()}/footpath_api_cache.db';
    final database = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) => db.execute('''
          CREATE TABLE $_table (
            owner_uid TEXT NOT NULL,
            cache_key TEXT NOT NULL,
            status_code INTEGER NOT NULL,
            body TEXT NOT NULL,
            headers_json TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (owner_uid, cache_key)
          )
        '''),
      ),
    );
    _databaseInstance = database;
    return database;
  }

  Future<void> put(
    String ownerUid,
    String cacheKey,
    CachedApiGet response,
  ) async {
    final db = await _database();
    await db.insert(_table, {
      'owner_uid': ownerUid,
      'cache_key': cacheKey,
      'status_code': response.statusCode,
      'body': response.body,
      'headers_json': jsonEncode(response.headers),
      'updated_at': _now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<CachedApiGet?> get(String ownerUid, String cacheKey) async {
    final db = await _database();
    final rows = await db.query(
      _table,
      where: 'owner_uid = ? AND cache_key = ?',
      whereArgs: [ownerUid, cacheKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final row = rows.single;
    final updatedAt = DateTime.parse(row['updated_at'] as String).toUtc();
    if (_now().toUtc().difference(updatedAt) >= maxAge) {
      await db.delete(
        _table,
        where: 'owner_uid = ? AND cache_key = ?',
        whereArgs: [ownerUid, cacheKey],
      );
      return null;
    }
    final decodedHeaders = jsonDecode(row['headers_json'] as String) as Map;
    return CachedApiGet(
      statusCode: row['status_code'] as int,
      body: row['body'] as String,
      headers: decodedHeaders.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
    );
  }

  /// Removes every cached response belonging to one signed-out account.
  Future<void> clearOwner(String ownerUid) async {
    final db = await _database();
    await db.delete(_table, where: 'owner_uid = ?', whereArgs: [ownerUid]);
  }

  Future<void> close() async {
    await _databaseInstance?.close();
    _databaseInstance = null;
  }
}
