import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/match_performance.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/match_providers.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';
import 'package:footpath_cebu/presentation/screens/edit_football_match_screen.dart';
import 'package:footpath_cebu/presentation/screens/edit_match_performance_screen.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';

class MatchRosterScreen extends ConsumerStatefulWidget {
  const MatchRosterScreen({super.key, required this.match});

  final FootballMatch match;

  @override
  ConsumerState<MatchRosterScreen> createState() => _MatchRosterScreenState();
}

class _MatchRosterScreenState extends ConsumerState<MatchRosterScreen> {
  late FootballMatch _match;

  @override
  void initState() {
    super.initState();
    _match = widget.match;
  }

  Future<void> _editMatch() async {
    final updated = await Navigator.of(context).push<FootballMatch>(
      MaterialPageRoute(
        builder: (_) => EditFootballMatchScreen(existing: _match),
      ),
    );
    if (updated != null && mounted) setState(() => _match = updated);
  }

  Future<void> _refresh() async {
    ref.invalidate(squadProvider);
    final _ = await ref.refresh(matchPerformancesProvider(_match.id).future);
  }

  @override
  Widget build(BuildContext context) {
    final squad = ref.watch(squadProvider);
    final performances = ref.watch(matchPerformancesProvider(_match.id));
    return Scaffold(
      appBar: AppBar(
        title: Text('vs ${_match.opponent}'),
        actions: [
          IconButton(
            onPressed: _editMatch,
            tooltip: 'Edit match',
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: squad.when(
        loading: () => const DashboardLoadingState(),
        error: (error, _) => DashboardErrorState(
          message: friendlyErrorMessage(error, 'Could not load the squad.'),
          onRetry: () => ref.invalidate(squadProvider),
        ),
        data: (players) => performances.when(
          loading: () => const DashboardLoadingState(),
          error: (error, _) => DashboardErrorState(
            message: friendlyErrorMessage(
              error,
              'Could not load match statistics.',
            ),
            onRetry: () => ref.invalidate(matchPerformancesProvider(_match.id)),
          ),
          data: (rows) => _RosterBody(
            match: _match,
            players: players,
            performances: rows,
            onRefresh: _refresh,
          ),
        ),
      ),
    );
  }
}

class _RosterBody extends StatelessWidget {
  const _RosterBody({
    required this.match,
    required this.players,
    required this.performances,
    required this.onRefresh,
  });

  final FootballMatch match;
  final List<Player> players;
  final List<MatchPerformance> performances;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final byPlayer = {for (final row in performances) row.playerId: row};
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${match.venue.label} · '
                          '${match.competition.isEmpty ? 'Match' : match.competition}',
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${performances.length} of ${players.length} players recorded',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    match.scoreLabel,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Player Statistics',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Tap a player to add or correct their match data.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (players.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('No players are registered in this club.'),
            )
          else
            for (final player in players)
              _PlayerPerformanceTile(
                match: match,
                player: player,
                performance: byPlayer[player.id],
              ),
        ],
      ),
    );
  }
}

class _PlayerPerformanceTile extends StatelessWidget {
  const _PlayerPerformanceTile({
    required this.match,
    required this.player,
    required this.performance,
  });

  final FootballMatch match;
  final Player player;
  final MatchPerformance? performance;

  @override
  Widget build(BuildContext context) {
    final saved = performance != null;
    return Card(
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EditMatchPerformanceScreen(
              match: match,
              player: player,
              existing: performance,
            ),
          ),
        ),
        leading: CircleAvatar(
          child: Text(player.name.isEmpty ? '?' : player.name[0]),
        ),
        title: Text(player.name),
        subtitle: Text(
          saved
              ? '${performance!.position} · Rating '
                    '${performance!.coachRating.toStringAsFixed(1)}'
              : '${player.position?.code ?? 'No position'} · Not recorded',
        ),
        trailing: Icon(
          saved ? Icons.check_circle : Icons.add_circle_outline,
          color: saved ? Colors.green : null,
        ),
      ),
    );
  }
}
