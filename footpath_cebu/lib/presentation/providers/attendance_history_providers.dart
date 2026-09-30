import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/core/di/attendance_providers.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';

class AttendanceHistoryState {
  const AttendanceHistoryState({
    required this.records,
    required this.nextOffset,
    this.isLoadingMore = false,
    this.loadMoreError,
  });

  final List<Attendance> records;
  final int? nextOffset;
  final bool isLoadingMore;
  final Object? loadMoreError;

  bool get hasMore => nextOffset != null;

  /// Returns an updated state while preserving fields not explicitly changed.
  AttendanceHistoryState copyWith({
    bool? isLoadingMore,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) => AttendanceHistoryState(
    records: records,
    nextOffset: nextOffset,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    loadMoreError: clearLoadMoreError
        ? null
        : loadMoreError ?? this.loadMoreError,
  );
}

class AttendanceHistoryController
    extends AsyncNotifier<AttendanceHistoryState> {
  AttendanceHistoryController(this.playerId);

  static const pageSize = 50;

  final String playerId;

  /// Loads the initial page for this feature when the provider starts.
  @override
  Future<AttendanceHistoryState> build() => _firstPage();

  /// Loads the first page and its next offset for the feature list.
  Future<AttendanceHistoryState> _firstPage() async {
    final page = await ref
        .read(getPlayerAttendancePageProvider)
        .call(playerId, offset: 0, limit: pageSize);
    return AttendanceHistoryState(
      records: page.items,
      nextOffset: page.nextOffset,
    );
  }

  /// Reloads the first page and exposes loading or error state to the view.
  Future<void> refresh() async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(_firstPage);
    if (ref.mounted) state = result;
  }

  /// Appends the next page; keeps existing rows visible if loading fails.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) return;
    state = AsyncData(
      current.copyWith(isLoadingMore: true, clearLoadMoreError: true),
    );
    try {
      final page = await ref
          .read(getPlayerAttendancePageProvider)
          .call(playerId, offset: current.nextOffset!, limit: pageSize);
      if (!ref.mounted) return;
      state = AsyncData(
        AttendanceHistoryState(
          records: List.unmodifiable([...current.records, ...page.items]),
          nextOffset: page.nextOffset,
        ),
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = AsyncData(
        current.copyWith(isLoadingMore: false, loadMoreError: error),
      );
    }
  }
}

final attendanceHistoryProvider = AsyncNotifierProvider.autoDispose
    .family<AttendanceHistoryController, AttendanceHistoryState, String>(
      AttendanceHistoryController.new,
    );
