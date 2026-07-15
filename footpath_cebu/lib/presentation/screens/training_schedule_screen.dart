import 'package:flutter/material.dart';

import 'package:footpath_cebu/core/di/service_locator.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/screens/schedule_session_screen.dart';
import 'package:footpath_cebu/presentation/viewmodels/training_schedule_viewmodel.dart';
import 'package:footpath_cebu/presentation/widgets/coach_bottom_nav.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/training_session_card.dart';

/// Coach Portal — the Training Schedule.
///
/// A thin View: it renders [TrainingScheduleViewModel] state and lets the coach
/// switch between Upcoming and Past sessions or open the scheduling form.
class TrainingScheduleScreen extends StatefulWidget {
  const TrainingScheduleScreen({super.key, required this.profile});

  /// The signed-in coach, forwarded to the shared bottom navigation.
  final UserProfile profile;

  @override
  State<TrainingScheduleScreen> createState() => _TrainingScheduleScreenState();
}

class _TrainingScheduleScreenState extends State<TrainingScheduleScreen> {
  late final TrainingScheduleViewModel _viewModel =
      TrainingScheduleViewModel(ServiceLocator.getTrainingSessions);

  bool _showPast = false;

  @override
  void initState() {
    super.initState();
    _viewModel.load();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _openScheduleForm() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ScheduleSessionScreen()),
    );
    if (created == true) {
      await _viewModel.load();
    }
  }

  void _logAttendance() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Attendance logging is coming soon.')),
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
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          return Column(
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
          );
        },
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
    if (_viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_viewModel.error != null) {
      return DashboardErrorState(
        message: _viewModel.error!,
        onRetry: _viewModel.load,
      );
    }
    final List<TrainingSession> sessions =
        _showPast ? _viewModel.past : _viewModel.upcoming;
    if (sessions.isEmpty) {
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
      onRefresh: _viewModel.load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: sessions.length,
        itemBuilder: (context, i) => TrainingSessionCard(
          session: sessions[i],
          onLogAttendance: _logAttendance,
        ),
      ),
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
