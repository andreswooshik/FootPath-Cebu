import 'package:footpath_cebu/domain/entities/attendance_sync_entry.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';

abstract class AttendanceSyncRepository {
  Future<List<AttendanceSyncEntry>> fetchEntries();
  Stream<List<AttendanceSyncEntry>> watchEntries();

  /// Requests delivery of waiting batches. Rejected batches require correction.
  Future<void> syncNow();
  Future<void> saveCorrection(
    AttendanceSyncEntry entry,
    List<Attendance> records,
  );
}
