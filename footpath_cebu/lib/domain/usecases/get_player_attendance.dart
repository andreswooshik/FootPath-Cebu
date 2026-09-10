import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/entities/page_slice.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';

/// Use case: load one player's attendance history (most recent first).
class GetPlayerAttendance {
  const GetPlayerAttendance(this._repository);

  final PlayerAttendanceReader _repository;

  Future<List<Attendance>> call(String playerId, {String? unlockToken}) =>
      _repository.fetchAttendanceForPlayer(playerId, unlockToken: unlockToken);
}

/// Use case: load one bounded window for an incrementally rendered history.
class GetPlayerAttendancePage {
  const GetPlayerAttendancePage(this._repository);

  final PlayerAttendanceReader _repository;

  Future<PageSlice<Attendance>> call(
    String playerId, {
    required int offset,
    required int limit,
    String? unlockToken,
  }) async {
    final repository = _repository;
    if (repository is PlayerAttendancePageReader) {
      return (repository as PlayerAttendancePageReader)
          .fetchAttendancePageForPlayer(
            playerId,
            offset: offset,
            limit: limit,
            unlockToken: unlockToken,
          );
    }
    final records = await repository.fetchAttendanceForPlayer(
      playerId,
      unlockToken: unlockToken,
    );
    final end = (offset + limit).clamp(0, records.length);
    return PageSlice(
      items: offset >= records.length
          ? const <Attendance>[]
          : records.sublist(offset, end),
      nextOffset: end < records.length ? end : null,
    );
  }
}
