import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/training_schedule_providers.dart';
import 'package:footpath_cebu/presentation/screens/log_attendance_screen.dart';
import 'package:footpath_cebu/presentation/screens/schedule_session_screen.dart';
import 'package:footpath_cebu/presentation/widgets/coach_bottom_nav.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
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

  void _openScheduleForm() {
    Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ScheduleSessionScreen()),
    );
  }

  void _logAttendance(TrainingSession session) {
    Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LogAttendanceScreen(
          session: session,
          profile: widget.profile,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.sports_soccer, size: 20),
            SizedBox(width: 8),
            Text('FootPath Cebu'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            tooltip: 'Notifications',
            onPressed: () {},
          ),
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
                FilledButton.icon(
                  onPressed: _openScheduleForm,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Schedule New Session'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
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
      bottomNavigationBar: CoachBottomNav(
        profile: widget.profile,
        selectedIndex: 1,
      ),
    );
  }

  Widget _buildBody() {
    final sessions =
        ref.watch(_showPast ? pastSessionsProvider : upcomingSessionsProvider);
    return sessions.when(
      loading: () => const Center(child: CircularProgressIndicator()),
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
            itemBuilder: (context, i) => TrainingSessionCard(
              session: list[i],
              onTap: () => _logAttendance(list[i]),
              onLogAttendance: () => _logAttendance(list[i]),
            ),
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
