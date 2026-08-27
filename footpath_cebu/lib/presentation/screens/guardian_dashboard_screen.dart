import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/guardian_dashboard_providers.dart';
import 'package:footpath_cebu/presentation/providers/player_privacy_pin_providers.dart';
import 'package:footpath_cebu/presentation/screens/attendance_history_screen.dart';
import 'package:footpath_cebu/presentation/screens/eligibility_history_screen.dart';
import 'package:footpath_cebu/presentation/screens/injury_history_screen.dart';
import 'package:footpath_cebu/presentation/screens/login_screen.dart';
import 'package:footpath_cebu/presentation/theme/app_theme.dart';
import 'package:footpath_cebu/presentation/widgets/attendance_status_chip.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/notification_bell.dart';
import 'package:footpath_cebu/presentation/widgets/player_card.dart';
import 'package:footpath_cebu/presentation/widgets/player_privacy_gate.dart';
import 'package:footpath_cebu/presentation/widgets/sign_out_confirmation.dart';
import 'package:footpath_cebu/presentation/widgets/stat_tile.dart';

class GuardianDashboardScreen extends ConsumerWidget {
  const GuardianDashboardScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    if (!await confirmSignOut(context) || !context.mounted) return;
    ref.read(privacyUnlockedPlayersProvider.notifier).clear();
    await ref.read(unregisterDeviceProvider)();
    await ref.read(signOutProvider)();
    if (!context.mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedChildProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Players'),
        actions: [
          const NotificationBell(),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => _signOut(context, ref),
          ),
        ],
      ),
      body: ref
          .watch(linkedPlayersProvider)
          .when(
            loading: () => const DashboardLoadingState(),
            error: (error, _) => DashboardErrorState(
              message: friendlyErrorMessage(
                error,
                'Something went wrong loading your children.',
              ),
              onRetry: () => ref.invalidate(linkedPlayersProvider),
            ),
            data: (children) {
              if (children.isEmpty) {
                return const Center(child: Text('No linked players yet.'));
              }
              if (selected == null) {
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _PlayerSelector(
                      children: children,
                      selectedId: null,
                      onChanged: (id) =>
                          ref.read(selectedChildIdProvider.notifier).select(id),
                    ),
                    const SizedBox(height: 24),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Choose a player to continue',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _PlayerSelector(
                      children: children,
                      selectedId: selected.id,
                      onChanged: (id) =>
                          ref.read(selectedChildIdProvider.notifier).select(id),
                    ),
                  ),
                  Expanded(
                    child: PlayerPrivacyGate(
                      player: selected,
                      isGuardian: true,
                      child: _GuardianUnlockedContent(selector: selected),
                    ),
                  ),
                ],
              );
            },
          ),
    ).animateScreenEntrance();
  }
}

class _GuardianUnlockedContent extends ConsumerWidget {
  const _GuardianUnlockedContent({required this.selector});

  final Player selector;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(selectedChildDetailsProvider(selector.id));
    return details.when(
      loading: () => const DashboardLoadingState(compact: true),
      error: (error, _) => DashboardErrorState(
        message: friendlyErrorMessage(error, 'Could not load player profile.'),
        onRetry: () =>
            ref.invalidate(selectedChildDetailsProvider(selector.id)),
      ),
      data: (player) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(childAttendanceProvider(player.id));
          ref.invalidate(selectedChildDetailsProvider(player.id));
          await ref.read(selectedChildDetailsProvider(player.id).future);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(player.name, style: Theme.of(context).textTheme.titleLarge),
            Text(
              '${player.ageTier.label} · ${player.position?.code ?? 'No position'}',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: PlayerCard(player: player),
              ),
            ),
            const SizedBox(height: 16),
            _StatRow(child: player),
            const SizedBox(height: 16),
            _RecentAttendanceCard(child: player),
            const SizedBox(height: 16),
            _InjuryHistoryCard(child: player),
          ],
        ),
      ),
    );
  }
}

class _PlayerSelector extends StatelessWidget {
  const _PlayerSelector({
    required this.children,
    required this.selectedId,
    required this.onChanged,
  });

  final List<Player> children;
  final String? selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: selectedId,
            hint: const Text('Choose a player'),
            items: [
              for (final child in children)
                DropdownMenuItem(value: child.id, child: Text(child.name)),
            ],
            onChanged: (id) {
              if (id != null) onChanged(id);
            },
          ),
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
    final eligibility = StatTile(
      icon: Icons.school_outlined,
      label: 'Academic Performance',
      value: child.academicEligibilityApplicable
          ? child.eligibility.label
          : 'N/A',
      color: child.academicEligibilityApplicable ? Colors.orange : Colors.grey,
      subtitle: child.academicEligibilityApplicable
          ? 'Tap for status history'
          : 'Available only to School clubs',
      onTap: child.academicEligibilityApplicable
          ? () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EligibilityHistoryScreen(
                  playerId: child.id,
                  playerName: child.name,
                ),
              ),
            )
          : null,
    );
    final attendanceTile = StatTile(
      icon: Icons.event_available_outlined,
      label: 'Attendance',
      value: '${attendance.presentPercent}%',
      subtitle: 'Last ${attendance.sessionCount} sessions',
      color: AppColors.teal,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final stack = constraints.maxWidth < 340 || textScale > 1.3;
        if (stack) {
          return Column(
            key: const Key('guardian-stats-stacked'),
            children: [eligibility, const SizedBox(height: 12), attendanceTile],
          );
        }
        return Row(
          key: const Key('guardian-stats-inline'),
          children: [
            Expanded(child: eligibility),
            const SizedBox(width: 12),
            Expanded(child: attendanceTile),
          ],
        );
      },
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
                MotionSkeleton(
                  width: double.infinity,
                  height: 40,
                  borderRadius: 12,
                ),
              ],
              error: (error, _) => [
                Text(friendlyErrorMessage(error, 'Could not load attendance.')),
              ],
              data: (records) => records.isEmpty
                  ? const [Text('No sessions recorded yet.')]
                  : [
                      for (final record in records.recent)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(record.sessionName ?? 'Training'),
                          subtitle: Text(formatShortDate(record.updatedAt)),
                          trailing: AttendanceStatusChip(status: record.status),
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

class _InjuryHistoryCard extends StatelessWidget {
  const _InjuryHistoryCard({required this.child});

  final Player child;

  @override
  Widget build(BuildContext context) {
    return MotionPress(
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.healing_outlined),
          title: const Text('Injury History'),
          subtitle: Text(
            'View ${child.name.split(' ').first}\'s reported injuries',
          ),
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
      ),
    );
  }
}
