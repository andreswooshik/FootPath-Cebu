import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/match_providers.dart';
import 'package:footpath_cebu/presentation/screens/edit_football_match_screen.dart';
import 'package:footpath_cebu/presentation/screens/match_roster_screen.dart';
import 'package:footpath_cebu/presentation/screens/tournament_schedule_screen.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';

class CoordinatorMatchesScreen extends ConsumerWidget {
  const CoordinatorMatchesScreen({super.key});

  Future<void> _createAdHocMatch(BuildContext context) async {
    await Navigator.of(context).push<FootballMatch>(
      MaterialPageRoute(builder: (_) => const EditFootballMatchScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(footballMatchesProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Match Statistics'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createAdHocMatch(context),
        icon: const Icon(Icons.add),
        label: const Text('Ad-hoc match'),
      ),
      body: matches.when(
        loading: () => const DashboardLoadingState(),
        error: (error, _) => DashboardErrorState(
          message: friendlyErrorMessage(error, 'Could not load matches.'),
          onRetry: () => ref.invalidate(footballMatchesProvider),
        ),
        data: (rows) => RefreshIndicator(
          onRefresh: () => ref.refresh(footballMatchesProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.event_available_outlined),
                  title: const Text('Record a scheduled result'),
                  subtitle: const Text(
                    'Choose a published fixture after the match is played.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const TournamentScheduleScreen(
                        canRecordResults: true,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Completed Matches',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Text(
                    'No match results recorded yet.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                for (final match in rows)
                  _CoordinatorMatchCard(
                    match: match,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MatchRosterScreen(
                          match: match,
                          mode: MatchRosterMode.coordinator,
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoordinatorMatchCard extends StatelessWidget {
  const _CoordinatorMatchCard({required this.match, required this.onTap});

  final FootballMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      leading: Icon(
        match.recordSource == MatchRecordSource.scheduled
            ? Icons.event_available_outlined
            : Icons.bolt_outlined,
      ),
      title: Text('vs ${match.opponent}'),
      subtitle: Text(
        '${formatShortDate(match.playedOn)} - '
        '${match.recordSource == MatchRecordSource.scheduled ? 'Scheduled' : 'Ad-hoc'}',
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
