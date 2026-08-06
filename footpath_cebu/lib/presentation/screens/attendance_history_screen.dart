import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/guardian_dashboard_providers.dart';
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
    final attendanceAsync = ref.watch(childAttendanceProvider(playerId));
    return Scaffold(
      appBar: AppBar(title: Text('Attendance · $playerName')),
      body: attendanceAsync.when(
        loading: () => const DashboardLoadingState(),
        error: (e, _) => DashboardErrorState(
          message: friendlyErrorMessage(
            e,
            'Something went wrong loading attendance.',
          ),
          onRetry: () => ref.invalidate(childAttendanceProvider(playerId)),
        ),
        data: (records) {
          if (records.isEmpty) {
            return const Center(child: Text('No attendance records yet.'));
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.refresh(childAttendanceProvider(playerId).future),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: records.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final record = records[index];
                return Card(
                  child: ListTile(
                    title: Text(record.sessionName ?? 'Training'),
                    subtitle: Text(formatFullDate(record.updatedAt)),
                    trailing: AttendanceStatusChip(status: record.status),
                  ),
                ).animateListItem(
                  key: ValueKey(record.updatedAt),
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
