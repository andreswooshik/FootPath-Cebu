import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/presentation/providers/attendance_history_providers.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/widgets/attendance_status_chip.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';

/// Full attendance history for one player, most recent first. Reached by
/// tapping "View Full History" on the Dashboard — a task/detail screen, not
/// a tab, so it has no [PortalBottomNav].
class AttendanceHistoryScreen extends ConsumerWidget {
  const AttendanceHistoryScreen({
    super.key,
    required this.playerId,
    required this.playerName,
  });

  final String playerId;
  final String playerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceAsync = ref.watch(attendanceHistoryProvider(playerId));
    return Scaffold(
      appBar: AppBar(title: Text('Attendance · $playerName')),
      body: attendanceAsync.when(
        loading: () => const DashboardLoadingState(),
        error: (e, _) => DashboardErrorState(
          message: friendlyErrorMessage(
            e,
            'Something went wrong loading attendance.',
          ),
          onRetry: () =>
              ref.read(attendanceHistoryProvider(playerId).notifier).refresh(),
        ),
        data: (history) {
          final records = history.records;
          if (records.isEmpty) {
            return const Center(child: Text('No attendance records yet.'));
          }
          return RefreshIndicator(
            onRefresh: () => ref
                .read(attendanceHistoryProvider(playerId).notifier)
                .refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: records.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == records.length) {
                  return _LoadMoreAttendance(
                    playerId: playerId,
                    history: history,
                  );
                }
                final record = records[index];
                return Card(
                  child: ListTile(
                    title: Text(record.sessionName ?? 'Training'),
                    subtitle: Text(formatFullDate(record.updatedAt)),
                    trailing: AttendanceStatusChip(status: record.status),
                  ),
                ).animateListItem(
                  key: ValueKey('${record.sessionId}-${record.updatedAt}'),
                  index: index,
                );
              },
            ),
          );
        },
      ),
    ).animateScreenEntrance();
  }
}

class _LoadMoreAttendance extends ConsumerWidget {
  const _LoadMoreAttendance({required this.playerId, required this.history});

  final String playerId;
  final AttendanceHistoryState history;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (history.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (history.loadMoreError != null) {
      return Column(
        children: [
          const Text('Could not load more attendance records.'),
          TextButton(
            onPressed: () => ref
                .read(attendanceHistoryProvider(playerId).notifier)
                .loadMore(),
            child: const Text('Try again'),
          ),
        ],
      );
    }
    if (!history.hasMore) return const SizedBox.shrink();
    return Center(
      child: OutlinedButton(
        onPressed: () =>
            ref.read(attendanceHistoryProvider(playerId).notifier).loadMore(),
        child: const Text('Load more'),
      ),
    );
  }
}
