import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';

/// Use case: save the coach's attendance and effort marks for one session.
class LogSessionAttendance {
  const LogSessionAttendance(this._repository);

  final SessionAttendanceWriter _repository;

  Future<List<Attendance>> call(String sessionId, List<Attendance> records) =>
      _repository.saveSessionAttendance(sessionId, records);
}
