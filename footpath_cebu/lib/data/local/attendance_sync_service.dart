import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:footpath_cebu/data/local/attendance_outbox.dart';
import 'package:footpath_cebu/data/local/attendance_write_queue.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';

/// Drains the [AttendanceOutbox] through the live repository whenever
/// connectivity returns.
///
/// Batches are replayed sequentially, oldest first, so the newest save for a
/// session lands last and wins (the endpoint replaces a session's records
/// wholesale). A batch that still fails with a network error stops the drain
/// and schedules a retry with capped exponential backoff. Only a known,
/// non-retryable HTTP client/validation rejection is retained for correction; authentication,
/// throttling, timeout, and server failures retain the coach's queued work.
///
/// Plain Dart aside from the connectivity plugin type, so tests can inject a
/// fake connectivity stream and never touch platform channels.
class AttendanceSyncService {
  AttendanceSyncService({
    required this._outbox,
    required this._inner,
    required this._ownerUid,
    this._connectivityStream,
    AttendanceWriteQueue? writeQueue,
  }) : _writeQueue = writeQueue ?? AttendanceWriteQueue();

  static const _initialBackoff = Duration(seconds: 5);
  static const _maxBackoff = Duration(minutes: 5);

  final AttendanceOutbox _outbox;
  final SessionAttendanceWriter _inner;
  final String? Function() _ownerUid;
  final AttendanceWriteQueue _writeQueue;
  final Stream<List<ConnectivityResult>>? _connectivityStream;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _retryTimer;
  Duration _backoff = _initialBackoff;
  bool _draining = false;
  bool _disposed = false;

  /// Begins watching connectivity. Also kicks one immediate drain so work
  /// queued before this session (e.g. pre-restart) syncs without waiting for
  /// a connectivity change. Safe to call once post-login.
  void start() {
    if (_disposed || _subscription != null) return;
    final stream = _connectivityStream ?? Connectivity().onConnectivityChanged;
    _subscription = stream.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) {
        _backoff = _initialBackoff;
        unawaited(drain());
      }
    });
    unawaited(drain());
  }

  /// Replays every queued batch in order. Public so tests (and a future
  /// manual "sync now" affordance) can invoke it directly.
  Future<void> drain() async {
    if (_disposed || _draining) return;
    _draining = true;
    try {
      await _writeQueue.run(_drainPending);
    } catch (_) {
      // Keep durable work if the local database or connectivity plugin fails.
      _scheduleRetry();
    } finally {
      _draining = false;
    }
  }

  Future<void> _drainPending() async {
    if (_disposed) return;
    final ownerUid = _ownerUid();
    if (ownerUid == null || ownerUid.isEmpty) return;
    final batches = await _outbox.pendingBatches(ownerUid);
    for (final batch in batches) {
      if (_disposed || _ownerUid() != ownerUid) return;
      try {
        await _inner.saveSessionAttendance(batch.sessionId, batch.records);
        await _outbox.markSynced(batch.id);
      } on AttendanceNetworkException catch (e) {
        // Still offline — keep the batch, stop, and retry later.
        await _outbox.markFailed(batch.id, e.message);
        if (_ownerUid() == ownerUid) _scheduleRetry();
        return;
      } on AttendanceRepositoryException catch (e) {
        if (e.isNonRetryableClientError) {
          // The server understood and permanently rejected this payload
          // (for example 400/404/422). Replaying it unchanged cannot work.
          await _outbox.markRejected(batch.id, e.message);
          continue;
        }
        await _outbox.markFailed(batch.id, e.message);
        // Unknown errors and retryable HTTP responses (401/403/408/429/5xx)
        // remain durable. A later sign-in, permission repair, or healthy
        // server may make the exact batch valid again.
        if (_ownerUid() == ownerUid) _scheduleRetry();
        return;
      }
    }
    _backoff = _initialBackoff;
  }

  void _scheduleRetry() {
    if (_disposed) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(_backoff, () => unawaited(drain()));
    final doubled = _backoff * 2;
    _backoff = doubled > _maxBackoff ? _maxBackoff : doubled;
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }
}
