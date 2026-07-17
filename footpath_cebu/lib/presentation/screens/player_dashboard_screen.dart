import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/guardian_dashboard_providers.dart';
import 'package:footpath_cebu/presentation/providers/player_dashboard_providers.dart';
import 'package:footpath_cebu/presentation/screens/attendance_history_screen.dart';
import 'package:footpath_cebu/presentation/screens/login_screen.dart';
import 'package:footpath_cebu/presentation/widgets/attendance_status_chip.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/player_card.dart';
import 'package:footpath_cebu/presentation/widgets/portal_bottom_nav.dart';
import 'package:footpath_cebu/presentation/widgets/stat_tile.dart';

/// Player Portal — the signed-in player's own profile and status.
///
/// A thin View over [myProfileProvider]. Read-only: players view their own
/// data but do not edit ratings or eligibility.
class PlayerDashboardScreen extends ConsumerWidget {
  const PlayerDashboardScreen({super.key});

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
        title: const Text('My Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => _signOut(context, ref),
          ),
        ],
      ),
      body: ref.watch(myProfileProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => DashboardErrorState(
              message: friendlyErrorMessage(
                e,
                'Something went wrong loading your profile.',
              ),
              onRetry: () => ref.invalidate(myProfileProvider),
            ),
            data: (player) => RefreshIndicator(
              onRefresh: () => ref.refresh(myProfileProvider.future),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    player.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    '${player.ageTier.label} · ${player.classYear}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: PlayerCard(player: player),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _StatRow(player: player),
                  const SizedBox(height: 16),
                  _RecentAttendanceCard(player: player),
                ],
              ),
            ),
          ),
      bottomNavigationBar: ref.watch(myProfileProvider).maybeWhen(
            data: (player) =>
                PortalBottomNav(player: player, selectedIndex: 0),
            orElse: () => null,
          ),
    );
  }
}

class _StatRow extends ConsumerWidget {
  const _StatRow({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendance =
        ref.watch(childAttendanceProvider(player.id)).value ?? const [];
    return Row(
      children: [
        Expanded(
          child: StatTile(
            icon: Icons.school_outlined,
            label: 'Academic Performance',
            value: player.eligibility.label,
            color: _eligibilityColor(player.eligibility),
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
  const _RecentAttendanceCard({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendance = ref.watch(childAttendanceProvider(player.id));
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
                      playerId: player.id,
                      playerName: player.name,
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
