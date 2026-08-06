import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';

/// Use case: load one player's attendance history (most recent first).
class GetPlayerAttendance {
  const GetPlayerAttendance(this._repository);

  final PlayerAttendanceReader _repository;

  Future<List<Attendance>> call(String playerId, {String? unlockToken}) =>
      _repository.fetchAttendanceForPlayer(playerId, unlockToken: unlockToken);
}
