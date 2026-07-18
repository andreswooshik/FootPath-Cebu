import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/guardian_dashboard_providers.dart';
import 'package:footpath_cebu/presentation/screens/attendance_history_screen.dart';
import 'package:footpath_cebu/presentation/screens/eligibility_history_screen.dart';
import 'package:footpath_cebu/presentation/screens/injury_history_screen.dart';
import 'package:footpath_cebu/presentation/screens/login_screen.dart';
import 'package:footpath_cebu/presentation/widgets/attendance_status_chip.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/theme/app_theme.dart';
import 'package:footpath_cebu/presentation/widgets/player_card.dart';
import 'package:footpath_cebu/presentation/widgets/portal_bottom_nav.dart';
import 'package:footpath_cebu/presentation/widgets/stat_tile.dart';

/// Guardian Portal — a read-only dashboard mirroring the Player portal, but
/// for the guardian's (first) linked child rather than the signed-in player.
///
/// A thin View over the guardian providers. Guardians view but never edit.
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
            data: (_) {
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
                    _RecentAttendanceCard(child: child),
                    const SizedBox(height: 16),
                    _InjuryHistoryCard(child: child),
                  ],
                ),
              );
            },
          ),
      bottomNavigationBar: ref.watch(selectedChildProvider) == null
          ? null
          : PortalBottomNav(
              player: ref.watch(selectedChildProvider)!,
              selectedIndex: 0,
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
            subtitle: 'Tap for status history',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EligibilityHistoryScreen(
                  playerId: child.id,
                  playerName: child.name,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatTile(
            icon: Icons.event_available_outlined,
            label: 'Attendance',
            value: '${attendance.presentPercent}%',
            subtitle: 'Last ${attendance.sessionCount} sessions',
            color: AppColors.teal,
          ),
        ),
      ],
    );
  }
}

/// Read-only entry point to the child's injury history. The server enforces
/// the same rule: a guardian reads a linked child's records, never writes.
class _InjuryHistoryCard extends StatelessWidget {
  const _InjuryHistoryCard({required this.child});

  final Player child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.healing_outlined),
        title: const Text('Injury History'),
        subtitle: Text("View ${child.name.split(' ').first}'s reported injuries"),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => InjuryHistoryScreen(
              playerId: child.id,
              playerName: child.name,
              readOnly: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentAttendanceCard extends ConsumerWidget {
  const _RecentAttendanceCard({required this.child});

  final Player child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendance = ref.watch(childAttendanceProvider(child.id));
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
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AttendanceHistoryScreen(
                      playerId: child.id,
                      playerName: child.name,
                    ),
                  ),
                ),
                child: const Text('View Full History'),
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
