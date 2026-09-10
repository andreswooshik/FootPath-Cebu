import 'dart:async';

/// Orders foreground attendance saves and background replay in this process.
/// The composition root supplies the same queue to both writers.
class AttendanceWriteQueue {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) async {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    await previous;
    try {
      return await action();
    } finally {
      released.complete();
    }
  }
}
