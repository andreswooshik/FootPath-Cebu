import 'package:flutter/material.dart';

import 'package:footpath_cebu/core/di/service_locator.dart';
import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/presentation/screens/login_screen.dart';
import 'package:footpath_cebu/presentation/viewmodels/guardian_dashboard_viewmodel.dart';
import 'package:footpath_cebu/presentation/widgets/attendance_status_chip.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/player_card.dart';
import 'package:footpath_cebu/presentation/widgets/stat_tile.dart';

/// Guardian Portal — a read-only dashboard for the guardian's linked children.
///
/// A thin View over [GuardianDashboardViewModel]. The guardian picks a child
/// (when more than one is linked) and sees that child's card, academic
/// eligibility, and attendance summary. Guardians view but never edit.
class GuardianDashboardScreen extends StatefulWidget {
  const GuardianDashboardScreen({super.key});

  @override
  State<GuardianDashboardScreen> createState() =>
      _GuardianDashboardScreenState();
}

class _GuardianDashboardScreenState extends State<GuardianDashboardScreen> {
  late final GuardianDashboardViewModel _viewModel = GuardianDashboardViewModel(
    ServiceLocator.getLinkedPlayers,
    ServiceLocator.getPlayerAttendance,
  );

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

  Future<void> _signOut() async {
    await ServiceLocator.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Players'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: _signOut,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          if (_viewModel.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_viewModel.error != null) {
            return DashboardErrorState(
              message: _viewModel.error!,
              onRetry: _viewModel.load,
            );
          }
          final child = _viewModel.selectedChild;
          if (child == null) {
            return const Center(child: Text('No linked players yet.'));
          }
          return RefreshIndicator(
            onRefresh: _viewModel.load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_viewModel.childCount > 1) _childSelector(child),
                Text(child.name, style: Theme.of(context).textTheme.titleLarge),
                Text(
                  '${child.ageTier} · ${child.position}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: PlayerCard(player: child),
                  ),
                ),
                const SizedBox(height: 16),
                _statRow(child),
                const SizedBox(height: 16),
                _recentAttendanceCard(),
              ],
            ),
          );
        },
      ),
      // Same pattern as the Coach dashboard: Dashboard is active; the other
      // tabs are placeholders until Schedule/Timeline/Profile are ported.
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (i) {
          if (i == 0) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Coming soon.')),
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            label: 'Schedule',
          ),
          NavigationDestination(
            icon: Icon(Icons.trending_up),
            label: 'Progress',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _childSelector(Player selected) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          segments: [
            for (final c in _viewModel.children)
              ButtonSegment(value: c.id, label: Text(c.name.split(' ').first)),
          ],
          selected: {selected.id},
          onSelectionChanged: (selection) =>
              _viewModel.selectChild(selection.first),
        ),
      ),
    );
  }

  Widget _statRow(Player child) {
    return Row(
      children: [
        Expanded(
          child: StatTile(
            icon: Icons.school_outlined,
            label: 'Academic Performance',
            value: child.eligibility.label,
            color: _eligibilityColor(child.eligibility),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatTile(
            icon: Icons.event_available_outlined,
            label: 'Attendance',
            value: '${_viewModel.attendancePercent}%',
            subtitle: 'Last ${_viewModel.sessionCount} sessions',
            color: const Color(0xFF1B5E20),
          ),
        ),
      ],
    );
  }

  Widget _recentAttendanceCard() {
    final recent = _viewModel.recentAttendance;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Attendance',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_viewModel.isLoadingAttendance)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (recent.isEmpty)
              const Text('No sessions recorded yet.')
            else
              for (final record in recent)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${record.sessionName ?? 'Training'} · '
                          '${formatShortDate(record.updatedAt)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      AttendanceStatusChip(status: record.status),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

Color _eligibilityColor(EligibilityStatus status) => switch (status) {
      EligibilityStatus.eligible => Colors.green,
      EligibilityStatus.notEligible => Colors.red,
      EligibilityStatus.pending => Colors.orange,
      EligibilityStatus.academicWarning => Colors.amber.shade800,
    };
