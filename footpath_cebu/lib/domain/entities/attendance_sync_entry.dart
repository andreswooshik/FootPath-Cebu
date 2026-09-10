import 'package:footpath_cebu/domain/entities/attendance.dart';

enum AttendanceDeliveryStatus {
  savedOnServer,
  waitingToSync,
  needsCorrection,
  unknown,
}

class AttendanceSyncEntry {
  const AttendanceSyncEntry({
    required this.sessionId,
    required this.records,
    required this.status,
    required this.recoveryKey,
    this.error,
  });

  final String sessionId;
  final List<Attendance> records;
  final AttendanceDeliveryStatus status;
  final String? error;

  /// Identifies the exact locally retained version, not an authorization token.
  final String recoveryKey;

  String get sessionName =>
      records.isNotEmpty && (records.first.sessionName?.isNotEmpty ?? false)
      ? records.first.sessionName!
      : 'Session $sessionId';
}
