import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/card_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/guardian_dashboard_providers.dart';
import 'package:footpath_cebu/presentation/providers/player_dashboard_providers.dart';
import 'package:footpath_cebu/presentation/screens/attendance_history_screen.dart';
import 'package:footpath_cebu/presentation/screens/eligibility_history_screen.dart';
import 'package:footpath_cebu/presentation/screens/injury_history_screen.dart';
import 'package:footpath_cebu/presentation/screens/login_screen.dart';
import 'package:footpath_cebu/presentation/widgets/attendance_status_chip.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/notification_bell.dart';
import 'package:footpath_cebu/presentation/widgets/player_card.dart';
import 'package:footpath_cebu/presentation/widgets/player_privacy_gate.dart';
import 'package:footpath_cebu/presentation/widgets/sign_out_confirmation.dart';
import 'package:footpath_cebu/presentation/widgets/stat_tile.dart';
import 'package:footpath_cebu/presentation/providers/player_privacy_pin_providers.dart';
import 'package:footpath_cebu/presentation/widgets/streak_counter.dart';
import 'package:footpath_cebu/presentation/widgets/tier_badge.dart';

/// Player Portal — the signed-in player's own profile and status.
///
/// A thin View over [myProfileProvider]. Read-only: players view their own
/// data but do not edit ratings or eligibility.
class PlayerDashboardScreen extends ConsumerWidget {
  const PlayerDashboardScreen({super.key});

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
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
          .watch(myProfileProvider)
          .when(
            loading: () => const DashboardLoadingState(),
            error: (e, _) => DashboardErrorState(
              message: friendlyErrorMessage(
                e,
                'Something went wrong loading your profile.',
              ),
              onRetry: () => ref.invalidate(myProfileProvider),
            ),
            data: (player) => PlayerPrivacyGate(
              player: player,
              requirePinSetup: true,
              child: RefreshIndicator(
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
                    const SizedBox(height: 12),
                    Center(child: TierBadge(tier: CardTier.forPlayer(player))),
                    const SizedBox(height: 16),
                    _StreakSection(player: player),
                    const SizedBox(height: 12),
                    _EligibilityTile(player: player),
                    const SizedBox(height: 16),
                    _RecentAttendanceCard(player: player),
                    const SizedBox(height: 16),
                    _InjuryHistoryCard(player: player),
                  ],
                ),
              ),
            ),
          ),
    ).animateScreenEntrance();
  }
}

/// The gamified attendance section — a streak flame instead of a raw "0%".
class _StreakSection extends ConsumerWidget {
  const _StreakSection({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendance =
        ref.watch(childAttendanceProvider(player.id)).value ?? const [];
    return StreakCounter(
      streak: attendance.currentStreak,
      presentPercent: attendance.presentPercent,
    );
  }
}

/// School standing in youth-friendly language — the muted eligibility enum
/// becomes an at-a-glance "ready to play?" call. Tapping opens the full
/// status-change timeline.
class _EligibilityTile extends StatelessWidget {
  const _EligibilityTile({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return StatTile(
      icon: Icons.school_outlined,
      label: 'Academic Eligibility',
      value: player.academicEligibilityApplicable
          ? _eligibilityHeadline(player.eligibility)
          : 'N/A',
      color: player.academicEligibilityApplicable
          ? _eligibilityColor(player.eligibility)
          : Colors.grey,
      subtitle: player.academicEligibilityApplicable
          ? 'Tap for status history'
          : 'Available only to School clubs',
      onTap: player.academicEligibilityApplicable
          ? () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EligibilityHistoryScreen(
                  playerId: player.id,
                  playerName: player.name,
                ),
              ),
            )
          : null,
    );
  }
}

String _eligibilityHeadline(EligibilityStatus status) => switch (status) {
  EligibilityStatus.eligible => 'Ready to Play! 🚀',
  EligibilityStatus.academicWarning => 'Almost there — hit the books 📚',
  EligibilityStatus.notEligible => 'Bench time — grades first 📖',
  EligibilityStatus.pending => 'Check pending ⏳',
};

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
                  child: MotionSkeleton(
                    width: double.infinity,
                    height: 40,
                    borderRadius: 12,
                  ),
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

/// Entry point to the player's own injury CRUD screen.
class _InjuryHistoryCard extends StatelessWidget {
  const _InjuryHistoryCard({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return MotionPress(
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.healing_outlined),
          title: const Text('Injury History'),
          subtitle: const Text('Log and track your injuries'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => InjuryHistoryScreen(
                playerId: player.id,
                playerName: player.name,
              ),
            ),
          ),
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
