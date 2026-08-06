import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';
import 'package:footpath_cebu/presentation/providers/attendance_log_providers.dart';

/// Fake repository that records the last save and can be told to fail, so the
/// controller's success and error paths are both exercised without a backend.
class _FakeAttendanceRepo implements AttendanceRepository {
  _FakeAttendanceRepo({this.existing = const [], this.fail = false});

  final List<Attendance> existing;
  final bool fail;
  String? savedSessionId;
  List<Attendance>? savedRecords;

  @override
  Future<List<Attendance>> fetchAttendanceForSession(String sessionId) async =>
      existing;

  @override
  Future<List<Attendance>> saveSessionAttendance(
    String sessionId,
    List<Attendance> records,
  ) async {
    if (fail) throw AttendanceRepositoryException('boom');
    savedSessionId = sessionId;
    savedRecords = records;
    return records;
  }

  @override
  Future<List<Attendance>> fetchAttendanceForPlayer(
    String playerId, {
    String? unlockToken,
  }) async => const [];
}

Attendance _present(String playerId) => Attendance(
  playerId: playerId,
  status: AttendanceStatus.present,
  updatedAt: DateTime(2026, 6, 28),
  sessionId: 't1',
);

void main() {
  ProviderContainer containerWith(_FakeAttendanceRepo repo) {
    final container = ProviderContainer(
      overrides: [attendanceRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('sessionAttendanceProvider', () {
    test('returns the records saved for that session', () async {
      final repo = _FakeAttendanceRepo(existing: [_present('p1')]);
      final container = containerWith(repo);

      final records = await container.read(
        sessionAttendanceProvider('t1').future,
      );
      expect(records.single.playerId, 'p1');
    });
  });

  group('AttendanceLogController.save', () {
    test('forwards records to the repository and returns true', () async {
      final repo = _FakeAttendanceRepo();
      final container = containerWith(repo);

      final ok = await container
          .read(attendanceLogControllerProvider.notifier)
          .save('t1', [_present('p1'), _present('p2')]);

      expect(ok, isTrue);
      expect(repo.savedSessionId, 't1');
      expect(repo.savedRecords!.map((r) => r.playerId), ['p1', 'p2']);
      expect(container.read(attendanceLogControllerProvider).hasError, isFalse);
    });

    test('returns false and records the error on failure', () async {
      final repo = _FakeAttendanceRepo(fail: true);
      final container = containerWith(repo);

      final ok = await container
          .read(attendanceLogControllerProvider.notifier)
          .save('t1', [_present('p1')]);

      expect(ok, isFalse);
      expect(container.read(attendanceLogControllerProvider).hasError, isTrue);
    });
  });
}
