import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:footpath_cebu/data/local/attendance_outbox.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';

/// Drains the [AttendanceOutbox] through the live repository whenever
/// connectivity returns.
///
/// Batches are replayed sequentially, oldest first, so the newest save for a
/// session lands last and wins (the endpoint replaces a session's records
/// wholesale). A batch that still fails with a network error stops the drain
/// and schedules a retry with capped exponential backoff; a batch rejected by
/// the server (validation) is dropped after being recorded — replaying it
/// forever could never succeed.
///
/// Plain Dart aside from the connectivity plugin type, so tests can inject a
/// fake connectivity stream and never touch platform channels.
class AttendanceSyncService {
  AttendanceSyncService({
    required this._outbox,
    required this._inner,
    this._connectivityStream,
  });

  static const _initialBackoff = Duration(seconds: 5);
  static const _maxBackoff = Duration(minutes: 5);

  final AttendanceOutbox _outbox;
  final SessionAttendanceWriter _inner;
  final Stream<List<ConnectivityResult>>? _connectivityStream;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _retryTimer;
  Duration _backoff = _initialBackoff;
  bool _draining = false;

  /// Begins watching connectivity. Also kicks one immediate drain so work
  /// queued before this session (e.g. pre-restart) syncs without waiting for
  /// a connectivity change. Safe to call once post-login.
  void start() {
    if (_subscription != null) return;
    final stream =
        _connectivityStream ?? Connectivity().onConnectivityChanged;
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
    if (_draining) return;
    _draining = true;
    try {
      final batches = await _outbox.pendingBatches();
      for (final batch in batches) {
        try {
          await _inner.saveSessionAttendance(batch.sessionId, batch.records);
          await _outbox.markSynced(batch.id);
        } on AttendanceNetworkException catch (e) {
          // Still offline — keep the batch, stop, and retry later.
          await _outbox.markFailed(batch.id, e.message);
          _scheduleRetry();
          return;
        } on AttendanceRepositoryException catch (e) {
          // The server understood and refused (validation): retrying the
          // identical payload can never succeed, so drop it and move on.
          await _outbox.markFailed(batch.id, e.message);
          await _outbox.markSynced(batch.id);
        }
      }
      _backoff = _initialBackoff;
    } finally {
      _draining = false;
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(_backoff, () => unawaited(drain()));
    final doubled = _backoff * 2;
    _backoff = doubled > _maxBackoff ? _maxBackoff : doubled;
  }

  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }
}
