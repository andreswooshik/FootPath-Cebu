import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/match_providers.dart';
import 'package:footpath_cebu/presentation/screens/match_roster_screen.dart';
import 'package:footpath_cebu/presentation/widgets/adaptive_inline_layout.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/responsive_content.dart';

class CoachMatchesScreen extends ConsumerWidget {
  const CoachMatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(footballMatchesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Match Ratings')),
      body: ResponsiveContent(
        child: matches.when(
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
                        'The Coordinator records match results and player statistics first.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: rows.length,
                    itemBuilder: (context, index) => _MatchCard(
                      match: rows[index],
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MatchRosterScreen(
                            match: rows[index],
                            mode: MatchRosterMode.coach,
                          ),
                        ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = AdaptiveLayoutPolicy.shouldStack(
          context,
          constraints.maxWidth,
        );
        final score = Text(
          match.scoreLabel,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        );
        return Card(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.15),
                    foregroundColor: color,
                    child: Text(match.outcome.substring(0, 1)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'vs ${match.opponent}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${formatShortDate(match.playedOn)} - '
                          '${match.competition.isEmpty ? match.venue.label : match.competition}',
                        ),
                        if (compact) ...[const SizedBox(height: 6), score],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!compact) ...[score, const SizedBox(width: 8)],
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
