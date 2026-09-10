import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/attendance_providers.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/entities/page_slice.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';
import 'package:footpath_cebu/presentation/providers/attendance_history_providers.dart';

class _PagedAttendanceRepository
    implements AttendanceRepository, PlayerAttendancePageReader {
  final requestedOffsets = <int>[];
  bool failSecondPage = false;

  Attendance _record(int offset) => Attendance(
    playerId: 'p1',
    sessionId: 's$offset',
    status: AttendanceStatus.present,
    updatedAt: DateTime.utc(2026, 9, 10).subtract(Duration(days: offset)),
  );

  @override
  Future<PageSlice<Attendance>> fetchAttendancePageForPlayer(
    String playerId, {
    required int offset,
    required int limit,
    String? unlockToken,
  }) async {
    requestedOffsets.add(offset);
    if (offset > 0 && failSecondPage) {
      throw AttendanceRepositoryException('second page failed');
    }
    return PageSlice(
      items: [_record(offset)],
      nextOffset: offset == 0 ? limit : null,
    );
  }

  @override
  Future<List<Attendance>> fetchAttendanceForPlayer(
    String playerId, {
    String? unlockToken,
  }) async => [_record(0)];

  @override
  Future<List<Attendance>> fetchAttendanceForSession(String sessionId) async =>
      const [];

  @override
  Future<List<Attendance>> saveSessionAttendance(
    String sessionId,
    List<Attendance> records,
  ) async => records;
}

void main() {
  ProviderContainer containerWith(_PagedAttendanceRepository repository) {
    final container = ProviderContainer(
      overrides: [attendanceRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('loads attendance history incrementally', () async {
    final repository = _PagedAttendanceRepository();
    final container = containerWith(repository);
    final provider = attendanceHistoryProvider('p1');
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);

    final first = await container.read(provider.future);
    expect(first.records.single.sessionId, 's0');
    expect(first.hasMore, isTrue);
    expect(repository.requestedOffsets, [0]);

    await container.read(provider.notifier).loadMore();
    final loaded = container.read(provider).requireValue;
    expect(loaded.records.map((record) => record.sessionId), ['s0', 's50']);
    expect(loaded.hasMore, isFalse);
    expect(repository.requestedOffsets, [0, 50]);
  });

  test('retains loaded attendance when a later page fails', () async {
    final repository = _PagedAttendanceRepository()..failSecondPage = true;
    final container = containerWith(repository);
    final provider = attendanceHistoryProvider('p1');
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);

    await container.read(provider.notifier).loadMore();

    final state = container.read(provider).requireValue;
    expect(state.records.single.sessionId, 's0');
    expect(state.loadMoreError, isA<AttendanceRepositoryException>());
    expect(state.hasMore, isTrue);
  });
}
