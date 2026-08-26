import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/guardian_dashboard_providers.dart';
import 'package:footpath_cebu/presentation/screens/match_statistics_screen.dart';
import 'package:footpath_cebu/presentation/theme/app_theme.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/player_privacy_gate.dart';

/// Progress tab — the coach's session-by-session feedback, most recent
/// first. There's no separate "ratings" data: a coach's effort score and
/// remark are recorded directly on the attendance record for that session
/// (see [LogAttendanceScreen]), so this screen is just those same attendance
/// records, filtered to the ones a coach actually left a note on.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({
    super.key,
    required this.player,
    this.isGuardian = false,
  });

  final Player player;
  final bool isGuardian;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = PlayerPrivacyGate(
      player: player,
      isGuardian: isGuardian,
      child: TabBarView(
        children: [
          PlayerMatchStatisticsView(playerId: player.id),
          _TrainingFeedbackView(playerId: player.id),
        ],
      ),
    );
    final scaffold = Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Progress'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Matches'),
            Tab(text: 'Training Feedback'),
          ],
        ),
      ),
      body: content,
    );
    return DefaultTabController(
      length: 2,
      child: scaffold,
    ).animateScreenEntrance();
  }
}

class _TrainingFeedbackView extends ConsumerWidget {
  const _TrainingFeedbackView({required this.playerId});

  final String playerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceAsync = ref.watch(childAttendanceProvider(playerId));
    return attendanceAsync.when(
      loading: () => const DashboardLoadingState(),
      error: (e, _) => DashboardErrorState(
        message: friendlyErrorMessage(
          e,
          'Something went wrong loading progress.',
        ),
        onRetry: () => ref.invalidate(childAttendanceProvider(playerId)),
      ),
      data: (records) {
        final feedback =
            records.where((a) => (a.note ?? '').trim().isNotEmpty).toList()
              ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        if (feedback.isEmpty) {
          return const Center(child: Text('No coach feedback yet.'));
        }
        return RefreshIndicator(
          onRefresh: () =>
              ref.refresh(childAttendanceProvider(playerId).future),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: feedback.length,
            itemBuilder: (context, index) =>
                _ProgressEntry(
                  record: feedback[index],
                  isLast: index == feedback.length - 1,
                ).animateListItem(
                  key: ValueKey(feedback[index].updatedAt),
                  index: index,
                ),
          ),
        );
      },
    );
  }
}

/// Buckets a 0-100 effort score into the label/colour shown on the entry.
({String label, Color color}) _intensity(int? effort) {
  final value = effort ?? 0;
  if (value >= 90) return (label: 'ELITE', color: AppColors.tealDark);
  if (value >= 67) return (label: 'HIGH', color: Colors.deepOrange);
  if (value >= 34) return (label: 'MED', color: Colors.orange);
  return (label: 'LOW', color: Colors.blueGrey);
}

class _ProgressEntry extends StatelessWidget {
  const _ProgressEntry({required this.record, required this.isLast});

  final Attendance record;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final intensity = _intensity(record.effort);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: intensity.color,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: Colors.grey.shade300),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            formatFullDate(record.updatedAt),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const Spacer(),
                          Chip(
                            label: Text(intensity.label),
                            labelStyle: TextStyle(
                              color: intensity.color,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                            backgroundColor: intensity.color.withValues(
                              alpha: 0.12,
                            ),
                            visualDensity: VisualDensity.compact,
                            side: BorderSide(color: intensity.color),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        record.sessionName ?? 'Training',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              '"${record.note}"',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(fontStyle: FontStyle.italic),
                            ),
                          ),
                          if (record.effort != null)
                            Text(
                              '${record.effort}%',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: intensity.color,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
