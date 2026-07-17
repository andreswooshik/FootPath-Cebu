import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';

/// Use case: load every attendance record already logged for one session.
class GetSessionAttendance {
  const GetSessionAttendance(this._repository);

  final SessionAttendanceReader _repository;

  Future<List<Attendance>> call(String sessionId) =>
      _repository.fetchAttendanceForSession(sessionId);
}
