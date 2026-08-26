import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/match_providers.dart';
import 'package:footpath_cebu/presentation/screens/edit_football_match_screen.dart';
import 'package:footpath_cebu/presentation/screens/match_roster_screen.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';

class CoachMatchesScreen extends ConsumerWidget {
  const CoachMatchesScreen({super.key});

  Future<void> _createMatch(BuildContext context) async {
    await Navigator.of(context).push<FootballMatch>(
      MaterialPageRoute(builder: (_) => const EditFootballMatchScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(footballMatchesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Match Records')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createMatch(context),
        icon: const Icon(Icons.add),
        label: const Text('Record Match'),
      ),
      body: matches.when(
        loading: () => const DashboardLoadingState(),
        error: (error, _) => DashboardErrorState(
          message: friendlyErrorMessage(error, 'Could not load matches.'),
          onRetry: () => ref.invalidate(footballMatchesProvider),
        ),
        data: (rows) => RefreshIndicator(
          onRefresh: () => ref.refresh(footballMatchesProvider.future),
          child: rows.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(32),
                  children: const [
                    SizedBox(height: 72),
                    Icon(Icons.sports_soccer_outlined, size: 64),
                    SizedBox(height: 16),
                    Text(
                      'No matches recorded yet.',
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Record a completed match, then add each player’s statistics.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: rows.length,
                  itemBuilder: (context, index) => _MatchCard(
                    match: rows[index],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MatchRosterScreen(match: rows[index]),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match, required this.onTap});

  final FootballMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (match.outcome) {
      'Win' => Colors.green,
      'Loss' => Colors.red,
      _ => Colors.orange,
    };
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          foregroundColor: color,
          child: Text(match.outcome.substring(0, 1)),
        ),
        title: Text('vs ${match.opponent}'),
        subtitle: Text(
          '${formatShortDate(match.playedOn)} · '
          '${match.competition.isEmpty ? match.venue.label : match.competition}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              match.scoreLabel,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
