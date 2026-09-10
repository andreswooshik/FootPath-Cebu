import 'dart:math';

abstract final class AttendanceRequestId {
  static final Random _random = Random.secure();

  static String create() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}
