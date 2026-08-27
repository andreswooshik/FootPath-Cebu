import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/domain/entities/player_progress.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/progress_providers.dart';
import 'package:footpath_cebu/presentation/screens/coach_matches_screen.dart';
import 'package:footpath_cebu/presentation/screens/match_statistics_screen.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';

/// Coach Portal — the Progress tab: per-player attendance and effort
/// aggregates for the whole squad (was a "Coming soon" stub).
class CoachProgressScreen extends ConsumerWidget {
  const CoachProgressScreen({super.key, required this.profile});

  /// The signed-in coach, forwarded to the shared bottom navigation.
  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(squadProgressProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Progress'),
        actions: [
          IconButton(
            tooltip: 'Manage match records',
            icon: const Icon(Icons.sports_score_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CoachMatchesScreen()),
            ),
          ),
        ],
      ),
      body: progress.when(
        loading: () => const DashboardLoadingState(),
        error: (e, _) => DashboardErrorState(
          message: friendlyErrorMessage(
            e,
            'Something went wrong loading squad progress.',
          ),
          onRetry: () => ref.invalidate(squadProgressProvider),
        ),
        data: (players) => RefreshIndicator(
          onRefresh: () => ref.refresh(squadProgressProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Squad Progress',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 2),
              Text(
                'Attendance and training effort across the squad.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              _SquadSummary(players: players),
              const SizedBox(height: 8),
              if (players.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: Center(child: Text('No players in your squad yet.')),
                )
              else
                for (var i = 0; i < players.length; i++)
                  _PlayerProgressCard(
                    progress: players[i],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PlayerMatchStatisticsScreen(
                          playerId: players[i].id,
                          playerName: players[i].name,
                        ),
                      ),
                    ),
                  ).animateListItem(key: ValueKey(players[i].id), index: i),
            ],
          ),
        ),
      ),
    ).animateScreenEntrance();
  }
}

/// Squad-wide headline numbers above the per-player list.
class _SquadSummary extends StatelessWidget {
  const _SquadSummary({required this.players});

  final List<PlayerProgress> players;

  @override
  Widget build(BuildContext context) {
    final rates = players
        .map((p) => p.attendanceRate)
        .whereType<double>()
        .toList();
    final efforts = players.map((p) => p.avgEffort).whereType<int>().toList();
    final avgRate = rates.isEmpty
        ? null
        : rates.reduce((a, b) => a + b) / rates.length;
    final avgEffort = efforts.isEmpty
        ? null
        : efforts.reduce((a, b) => a + b) ~/ efforts.length;

    Widget stat(String label, String value) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            stat('Players', '${players.length}'),
            stat(
              'Avg attendance',
              avgRate == null ? '—' : '${(avgRate * 100).round()}%',
            ),
            stat('Avg effort', avgEffort == null ? '—' : '$avgEffort'),
          ],
        ),
      ),
    );
  }
}

class _PlayerProgressCard extends StatelessWidget {
  const _PlayerProgressCard({required this.progress, required this.onTap});

  final PlayerProgress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rate = progress.attendanceRate;
    final subtitle = [
      if (progress.position != null) progress.position!.code,
      progress.ageTier.label,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          progress.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (progress.avgEffort != null)
                    Column(
                      children: [
                        Text(
                          '${progress.avgEffort}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: cs.primary,
                              ),
                        ),
                        Text(
                          'EFFORT',
                          style: Theme.of(
                            context,
                          ).textTheme.labelSmall?.copyWith(letterSpacing: 0.6),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (rate == null)
                Text(
                  'No attendance recorded yet.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                )
              else ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: rate,
                    minHeight: 8,
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${(rate * 100).round()}% attendance — '
                  '${progress.present} present · ${progress.absent} absent · '
                  '${progress.excused} excused',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
