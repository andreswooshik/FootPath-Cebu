import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/match_performance.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/match_providers.dart';
import 'package:footpath_cebu/presentation/screens/edit_football_match_screen.dart';
import 'package:footpath_cebu/presentation/screens/edit_match_performance_screen.dart';
import 'package:footpath_cebu/presentation/screens/edit_match_rating_screen.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';

enum MatchRosterMode { coordinator, coach }

class MatchRosterScreen extends ConsumerStatefulWidget {
  const MatchRosterScreen({super.key, required this.match, required this.mode});

  final FootballMatch match;
  final MatchRosterMode mode;

  @override
  ConsumerState<MatchRosterScreen> createState() => _MatchRosterScreenState();
}

class _MatchRosterScreenState extends ConsumerState<MatchRosterScreen> {
  late FootballMatch _match;

  bool get _isCoordinator => widget.mode == MatchRosterMode.coordinator;

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
    final _ = await ref.refresh(matchRosterProvider(_match.id).future);
  }

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(matchRosterProvider(_match.id));
    return Scaffold(
      appBar: AppBar(
        title: Text('vs ${_match.opponent}'),
        actions: [
          if (_isCoordinator)
            IconButton(
              onPressed: _editMatch,
              tooltip: 'Edit match result',
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: roster.when(
        loading: () => const DashboardLoadingState(),
        error: (error, _) => DashboardErrorState(
          message: friendlyErrorMessage(error, 'Could not load the roster.'),
          onRetry: () => ref.invalidate(matchRosterProvider(_match.id)),
        ),
        data: (players) => _RosterBody(
          match: _match,
          mode: widget.mode,
          players: players,
          onRefresh: _refresh,
        ),
      ),
    );
  }
}

class _RosterBody extends StatelessWidget {
  const _RosterBody({
    required this.match,
    required this.mode,
    required this.players,
    required this.onRefresh,
  });

  final FootballMatch match;
  final MatchRosterMode mode;
  final List<MatchRosterPlayer> players;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final recorded = players.where((row) => row.performance != null).length;
    final rated = players
        .where((row) => row.ratingStatus == MatchRatingStatus.rated)
        .length;
    final coordinator = mode == MatchRosterMode.coordinator;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                          '${match.venue.label} - '
                          '${match.competition.isEmpty ? 'Match' : match.competition}',
                        ),
                        const SizedBox(height: 4),
                        Text(
                          coordinator
                              ? '$recorded of ${players.length} players recorded'
                              : '$rated of $recorded recorded players rated',
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
            coordinator ? 'Player Statistics' : 'Coach Ratings',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            coordinator
                ? 'Record objective match data. Coach ratings stay private and appear only as a status.'
                : 'Rate a player after the Coordinator records their match statistics.',
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
                mode: mode,
                player: player,
                onChanged: onRefresh,
              ),
        ],
      ),
    );
  }
}

class _PlayerPerformanceTile extends StatelessWidget {
  const _PlayerPerformanceTile({
    required this.match,
    required this.mode,
    required this.player,
    required this.onChanged,
  });

  final FootballMatch match;
  final MatchRosterMode mode;
  final MatchRosterPlayer player;
  final Future<void> Function() onChanged;

  Future<void> _open(BuildContext context) async {
    if (mode == MatchRosterMode.coach && player.performance == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => mode == MatchRosterMode.coordinator
            ? EditMatchPerformanceScreen(
                match: match,
                player: player,
                existing: player.performance,
              )
            : EditMatchRatingScreen(match: match, player: player),
      ),
    );
    await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final saved = player.performance != null;
    final coordinator = mode == MatchRosterMode.coordinator;
    final position = saved
        ? player.performance!.position
        : player.registeredPosition.isEmpty
        ? 'No position'
        : player.registeredPosition;
    final status = player.ratingStatus.label;
    final rating = player.performance?.coachRating;
    return Card(
      child: ListTile(
        onTap: coordinator || saved ? () => _open(context) : null,
        leading: CircleAvatar(
          child: Text(player.name.isEmpty ? '?' : player.name[0]),
        ),
        title: Text(player.name),
        subtitle: Text(
          coordinator
              ? '$position - ${saved ? status : 'Not recorded'}'
              : '$position - $status${rating == null ? '' : ' (${rating.toStringAsFixed(1)})'}',
        ),
        trailing: Icon(
          coordinator
              ? saved
                    ? Icons.edit_outlined
                    : Icons.add_circle_outline
              : !saved
              ? Icons.hourglass_empty
              : player.ratingStatus == MatchRatingStatus.rated
              ? Icons.edit_outlined
              : Icons.star_outline,
          color: saved ? Theme.of(context).colorScheme.primary : null,
        ),
      ),
    );
  }
}
