import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/match_performance.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/match_providers.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/performance_trend_chart.dart';

enum MatchHistoryRange { lastFive, lastTen, all }

extension on MatchHistoryRange {
  String get label => switch (this) {
    MatchHistoryRange.lastFive => 'Last 5',
    MatchHistoryRange.lastTen => 'Last 10',
    MatchHistoryRange.all => 'All',
  };

  int? get limit => switch (this) {
    MatchHistoryRange.lastFive => 5,
    MatchHistoryRange.lastTen => 10,
    MatchHistoryRange.all => null,
  };
}

/// Route wrapper used from a coach's player profile.
class PlayerMatchStatisticsScreen extends StatelessWidget {
  const PlayerMatchStatisticsScreen({
    super.key,
    required this.playerId,
    required this.playerName,
  });

  final String playerId;
  final String playerName;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('$playerName · Match Performance')),
    body: PlayerMatchStatisticsView(playerId: playerId),
  );
}

/// Reusable statistics body for both the player tab and coach route.
class PlayerMatchStatisticsView extends ConsumerStatefulWidget {
  const PlayerMatchStatisticsView({super.key, required this.playerId});

  final String playerId;

  @override
  ConsumerState<PlayerMatchStatisticsView> createState() =>
      _PlayerMatchStatisticsViewState();
}

class _PlayerMatchStatisticsViewState
    extends ConsumerState<PlayerMatchStatisticsView> {
  MatchHistoryRange _range = MatchHistoryRange.lastFive;

  @override
  Widget build(BuildContext context) {
    final statistics = ref.watch(
      playerMatchStatisticsProvider(widget.playerId),
    );
    return statistics.when(
      loading: () => const DashboardLoadingState(),
      error: (error, _) => DashboardErrorState(
        message: friendlyErrorMessage(
          error,
          'Could not load match statistics.',
        ),
        onRetry: () =>
            ref.invalidate(playerMatchStatisticsProvider(widget.playerId)),
      ),
      data: _buildStatistics,
    );
  }

  Widget _buildStatistics(PlayerMatchStatistics statistics) {
    final all = statistics.performances;
    final limit = _range.limit;
    final visible = limit == null || all.length <= limit
        ? all
        : all.take(limit).toList(growable: false);
    if (all.isEmpty) {
      return RefreshIndicator(
        onRefresh: () =>
            ref.refresh(playerMatchStatisticsProvider(widget.playerId).future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          children: const [
            SizedBox(height: 72),
            Icon(Icons.sports_soccer_outlined, size: 64),
            SizedBox(height: 16),
            Text(
              'No match statistics recorded yet.',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'Statistics will appear after a coach records a completed match.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final summary = _range == MatchHistoryRange.all
        ? statistics.summary
        : MatchPerformanceSummary.fromPerformances(visible);
    final hasGoalkeeperRow = visible.any((row) => row.position == 'GK');
    return RefreshIndicator(
      onRefresh: () =>
          ref.refresh(playerMatchStatisticsProvider(widget.playerId).future),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${_range.label} Summary',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          GridView.extent(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            maxCrossAxisExtent: 180,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.2,
            children: [
              _SummaryTile(label: 'MATCHES', value: '${summary.matchesPlayed}'),
              _SummaryTile(label: 'GOALS', value: '${summary.goals}'),
              _SummaryTile(label: 'ASSISTS', value: '${summary.assists}'),
              _SummaryTile(
                label: 'RATING',
                value: summary.averageRating?.toStringAsFixed(1) ?? '—',
              ),
              _SummaryTile(
                label: 'PASS %',
                value: summary.passCompletionRate == null
                    ? '—'
                    : '${summary.passCompletionRate!.round()}%',
              ),
              _SummaryTile(
                label: hasGoalkeeperRow ? 'SAVES' : 'TACKLES',
                value: '${hasGoalkeeperRow ? summary.saves : summary.tackles}',
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Performance Trend',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              DropdownButton<MatchHistoryRange>(
                value: _range,
                onChanged: (value) {
                  if (value != null) setState(() => _range = value);
                },
                items: MatchHistoryRange.values
                    .map(
                      (range) => DropdownMenuItem(
                        value: range,
                        child: Text(range.label),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: PerformanceTrendChart(
                ratings: visible.reversed
                    .map((row) => row.coachRating)
                    .toList(growable: false),
                pointLabels: visible.reversed
                    .map((row) => formatShortDate(row.match.playedOn))
                    .toList(growable: false),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Match History', style: Theme.of(context).textTheme.titleMedium),
          if (_range == MatchHistoryRange.all &&
              summary.matchesPlayed > visible.length) ...[
            const SizedBox(height: 4),
            Text(
              'Showing the newest ${visible.length} of ${summary.matchesPlayed} matches. The summary includes all matches.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          for (final performance in visible)
            _MatchPerformanceCard(performance: performance),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}

class _MatchPerformanceCard extends StatelessWidget {
  const _MatchPerformanceCard({required this.performance});

  final MatchPerformance performance;

  @override
  Widget build(BuildContext context) {
    final match = performance.match;
    final passRate = performance.passCompletionRate;
    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(
          child: performance.coachRating == null
              ? const Icon(Icons.hourglass_empty, size: 18)
              : Text(performance.coachRating!.toStringAsFixed(1)),
        ),
        title: Text('vs ${match.opponent} · ${match.scoreLabel}'),
        subtitle: Text(
          '${formatShortDate(match.playedOn)} · ${match.competition.isEmpty ? match.venue.label : match.competition}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _InlineStat('Minutes', '${performance.minutesPlayed}'),
              _InlineStat('Goals', '${performance.goals}'),
              _InlineStat('Assists', '${performance.assists}'),
              _InlineStat(
                'Shots',
                '${performance.shotsOnTarget}/${performance.shots} on target',
              ),
              _InlineStat(
                'Passing',
                passRate == null ? '—' : '${passRate.round()}%',
              ),
              _InlineStat('Tackles', '${performance.tackles}'),
              if (performance.position == 'GK')
                _InlineStat('Saves', '${performance.saves}'),
            ],
          ),
          if (performance.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              performance.notes,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  const _InlineStat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 92,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}
