import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/guardian_dashboard_providers.dart';
import 'package:footpath_cebu/presentation/screens/login_screen.dart';
import 'package:footpath_cebu/presentation/widgets/attendance_status_chip.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/player_card.dart';
import 'package:footpath_cebu/presentation/widgets/stat_tile.dart';

/// Guardian Portal — a read-only dashboard for the guardian's linked children.
///
/// A thin View over the guardian providers. The guardian picks a child (when
/// more than one is linked) and sees that child's card, academic eligibility,
/// and attendance summary. Guardians view but never edit.
class GuardianDashboardScreen extends ConsumerWidget {
  const GuardianDashboardScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await ref.read(signOutProvider)();
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Players'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => _signOut(context, ref),
          ),
        ],
      ),
      body: ref.watch(linkedPlayersProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => DashboardErrorState(
              message: friendlyErrorMessage(
                e,
                'Something went wrong loading your children.',
              ),
              onRetry: () => ref.invalidate(linkedPlayersProvider),
            ),
            data: (children) {
              final child = ref.watch(selectedChildProvider);
              if (child == null) {
                return const Center(child: Text('No linked players yet.'));
              }
              return RefreshIndicator(
                onRefresh: () {
                  ref.invalidate(childAttendanceProvider);
                  return ref.refresh(linkedPlayersProvider.future);
                },
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (children.length > 1)
                      _ChildSelector(children: children, selected: child),
                    Text(
                      child.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${child.ageTier.label} · ${child.position?.code ?? 'No position'}',
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
                    _StatRow(child: child),
                    const SizedBox(height: 16),
                    _RecentAttendanceCard(childId: child.id),
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
}

/// Switches the active child; their attendance swaps in automatically because
/// the attendance provider is keyed by child id.
class _ChildSelector extends ConsumerWidget {
  const _ChildSelector({required this.children, required this.selected});

  final List<Player> children;
  final Player selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          segments: [
            for (final c in children)
              ButtonSegment(value: c.id, label: Text(c.name.split(' ').first)),
          ],
          selected: {selected.id},
          onSelectionChanged: (selection) => ref
              .read(selectedChildIdProvider.notifier)
              .select(selection.first),
        ),
      ),
    );
  }
}

class _StatRow extends ConsumerWidget {
  const _StatRow({required this.child});

  final Player child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendance =
        ref.watch(childAttendanceProvider(child.id)).value ?? const [];
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
            value: '${attendance.presentPercent}%',
            subtitle: 'Last ${attendance.sessionCount} sessions',
            color: const Color(0xFF1B5E20),
          ),
        ),
      ],
    );
  }
}

class _RecentAttendanceCard extends ConsumerWidget {
  const _RecentAttendanceCard({required this.childId});

  final String childId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendance = ref.watch(childAttendanceProvider(childId));
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
            ...attendance.when(
              loading: () => const [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (e, _) => [
                Text(
                  friendlyErrorMessage(
                    e,
                    'Something went wrong loading attendance.',
                  ),
                ),
              ],
              data: (records) => records.isEmpty
                  ? const [Text('No sessions recorded yet.')]
                  : [
                      for (final record in records.recent)
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
