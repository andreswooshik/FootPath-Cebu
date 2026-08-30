import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/providers/attendance_log_providers.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/training_schedule_providers.dart';
import 'package:footpath_cebu/presentation/screens/log_attendance_screen.dart';
import 'package:footpath_cebu/presentation/screens/schedule_session_screen.dart';
import 'package:footpath_cebu/presentation/screens/tournament_schedule_screen.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/notification_bell.dart';
import 'package:footpath_cebu/presentation/widgets/training_session_card.dart';

/// Coach Portal — the Training Schedule.
///
/// A thin View over the schedule providers: it lets the coach switch between
/// Upcoming and Past sessions or open the scheduling form. Scheduling a new
/// session invalidates the schedule provider, so the list refreshes without
/// this screen doing anything.
class TrainingScheduleScreen extends ConsumerStatefulWidget {
  const TrainingScheduleScreen({super.key, required this.profile});

  /// The signed-in coach, forwarded to the shared bottom navigation.
  final UserProfile profile;

  @override
  ConsumerState<TrainingScheduleScreen> createState() =>
      _TrainingScheduleScreenState();
}

class _TrainingScheduleScreenState
    extends ConsumerState<TrainingScheduleScreen> {
  bool _showPast = false;
  final Set<String> _openingSessionIds = {};

  void _openScheduleForm() {
    Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ScheduleSessionScreen()),
    );
  }

  void _editSession(TrainingSession session) {
    Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ScheduleSessionScreen(existing: session),
      ),
    );
  }

  Future<void> _cancelSession(TrainingSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this session?'),
        content: Text(
          '"${session.title}" will be removed from the schedule and players '
          'and guardians will be notified. Recorded attendance is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep session'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel session'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await ref
        .read(scheduleSessionControllerProvider.notifier)
        .cancel(session.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '"${session.title}" cancelled.'
              : friendlyErrorMessage(
                  ref.read(scheduleSessionControllerProvider).error,
                  'Could not cancel the session. Please try again.',
                ),
        ),
      ),
    );
  }

  Future<void> _logAttendance(TrainingSession session) async {
    if (_openingSessionIds.contains(session.id)) return;
    setState(() => _openingSessionIds.add(session.id));

    List<Attendance> existing;
    try {
      existing = await ref.read(sessionAttendanceProvider(session.id).future);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              error,
              'Could not load the saved attendance. Please try again.',
            ),
          ),
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => _openingSessionIds.remove(session.id));
    }

    if (!mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LogAttendanceScreen(
          session: session,
          profile: widget.profile,
          initialAttendance: existing,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Training'),
        actions: [
          IconButton(
            tooltip: 'Tournament schedule',
            icon: const Icon(Icons.emoji_events_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const TournamentScheduleScreen(canManageRosters: true),
              ),
            ),
          ),
          const NotificationBell(),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Training Schedule',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  "Manage your squad's development drills and "
                  'tactical sessions.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),

                const SizedBox(height: 14),
                _ScheduleTabs(
                  showPast: _showPast,
                  onChanged: (past) => setState(() => _showPast = past),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openScheduleForm,
        tooltip: 'Schedule new session',
        child: const Icon(Icons.add),
      ),
    ).animateScreenEntrance();
  }

  Widget _buildBody() {
    final sessions = ref.watch(
      _showPast ? pastSessionsProvider : upcomingSessionsProvider,
    );
    return sessions.when(
      loading: () => const DashboardLoadingState(),
      error: (e, _) => DashboardErrorState(
        message: friendlyErrorMessage(
          e,
          'Something went wrong loading the schedule.',
        ),
        onRetry: () => ref.invalidate(trainingSessionsProvider),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Text(
              _showPast
                  ? 'No past sessions yet.'
                  : 'No upcoming sessions. Schedule one to get started.',
              textAlign: TextAlign.center,
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref.refresh(trainingSessionsProvider.future),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final session = list[i];
              // A visible card warms its saved-attendance request before the
              // coach taps it. The route still awaits and passes the snapshot,
              // so even a very fast tap cannot paint a false blank roll call.
              ref.watch(sessionAttendanceProvider(session.id));
              return TrainingSessionCard(
                session: session,
                isLoading: _openingSessionIds.contains(session.id),
                onTap: () => _logAttendance(session),
                onLogAttendance: () => _logAttendance(session),
                // Completed sessions are historical records. Keep attendance
                // access where its grace window allows it, but only future and
                // today's sessions may be changed or cancelled.
                onEdit: _showPast ? null : () => _editSession(session),
                onCancelSession: _showPast
                    ? null
                    : () => _cancelSession(session),
              ).animateListItem(key: ValueKey(session.id), index: i);
            },
          ),
        );
      },
    );
  }
}

/// The Upcoming / Past Sessions segmented toggle.
class _ScheduleTabs extends StatelessWidget {
  const _ScheduleTabs({required this.showPast, required this.onChanged});

  final bool showPast;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TabButton(
            label: 'Upcoming',
            selected: !showPast,
            onTap: () => onChanged(false),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TabButton(
            label: 'Past Sessions',
            selected: showPast,
            onTap: () => onChanged(true),
          ),
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primary : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
