import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/match_performance.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/match_providers.dart';
import 'package:footpath_cebu/presentation/theme/app_theme.dart';
import 'package:footpath_cebu/presentation/widgets/adaptive_inline_layout.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/match_trend_metric.dart';
import 'package:footpath_cebu/presentation/widgets/match_type_filter.dart';
import 'package:footpath_cebu/presentation/widgets/performance_trend_chart.dart';
import 'package:footpath_cebu/presentation/widgets/responsive_content.dart';

enum MatchHistoryRange { lastFive, lastTen, all }

extension on MatchHistoryRange {
  String get label => switch (this) {
    MatchHistoryRange.lastFive => 'Last 5',
    MatchHistoryRange.lastTen => 'Last 10',
    MatchHistoryRange.all => 'All dates',
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

/// Match history and per-match statistics used in the Progress > Matches tab.
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
  MatchTypeFilter _matchType = MatchTypeFilter.all;
  MatchTrendMetric _metric = MatchTrendMetric.rating;

  @override
  Widget build(BuildContext context) {
    final statistics = ref.watch(
      playerMatchStatisticsProvider(widget.playerId),
    );
    return ResponsiveContent(
      child: statistics.when(
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
      ),
    );
  }

  Widget _buildStatistics(PlayerMatchStatistics statistics) {
    final all = [...statistics.performances]
      ..sort((a, b) => b.match.playedOn.compareTo(a.match.playedOn));
    if (all.isEmpty) return _emptyAllMatches();

    final filtered = all
        .where((row) {
          final isTournament = row.match.category == MatchCategory.tournament;
          return switch (_matchType) {
            MatchTypeFilter.all => true,
            MatchTypeFilter.regular => !isTournament,
            MatchTypeFilter.tournaments => isTournament,
          };
        })
        .toList(growable: false);
    final limit = _range.limit;
    final visible = limit == null || filtered.length <= limit
        ? filtered
        : filtered.take(limit).toList(growable: false);

    return RefreshIndicator(
      onRefresh: () =>
          ref.refresh(playerMatchStatisticsProvider(widget.playerId).future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Match History',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Review regular matches and tournaments together or separately.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          MatchTypeFilterBar(
            selected: _matchType,
            onSelected: (value) => setState(() => _matchType = value),
          ),
          const SizedBox(height: 16),
          if (filtered.isEmpty)
            _FilteredMatchesEmptyState(matchType: _matchType)
          else ...[
            _SummaryHeader(
              matchType: _matchType,
              range: _range,
              onRangeChanged: (value) => setState(() => _range = value),
            ),
            const SizedBox(height: 12),
            _SummaryGrid(
              summary: MatchPerformanceSummary.fromPerformances(visible),
              hasGoalkeeperRow: visible.any((row) => row.position == 'GK'),
            ),
            const SizedBox(height: 24),
            Text(
              'Your Performance Over Time',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'See how your match rating and skills have changed from earlier matches to your most recent matches.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            _MetricSelector(
              value: _metric,
              onChanged: (value) => setState(() => _metric = value),
            ),
            const SizedBox(height: 8),
            _TrendPanel(metric: _metric, performances: visible),
            const SizedBox(height: 24),
            Text(
              '${_matchType.label} · ${visible.length}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final performance in visible)
              _MatchPerformanceCard(performance: performance),
          ],
        ],
      ),
    );
  }

  Widget _emptyAllMatches() => RefreshIndicator(
    onRefresh: () =>
        ref.refresh(playerMatchStatisticsProvider(widget.playerId).future),
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: const [
        SizedBox(height: 72),
        Icon(Icons.sports_soccer_outlined, size: 64),
        SizedBox(height: 16),
        Text('No match statistics recorded yet.', textAlign: TextAlign.center),
        SizedBox(height: 8),
        Text(
          'Statistics will appear after a coach records a completed match.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.matchType,
    required this.range,
    required this.onRangeChanged,
  });

  final MatchTypeFilter matchType;
  final MatchHistoryRange range;
  final ValueChanged<MatchHistoryRange> onRangeChanged;

  Widget _dropdown({required bool expanded}) =>
      DropdownButton<MatchHistoryRange>(
        value: range,
        isExpanded: expanded,
        borderRadius: BorderRadius.circular(14),
        onChanged: (value) {
          if (value != null) onRangeChanged(value);
        },
        items: [
          for (final option in MatchHistoryRange.values)
            DropdownMenuItem(
              value: option,
              child: Text(option.label, overflow: TextOverflow.ellipsis),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) => AdaptiveInlineLayout(
    spacing: 16,
    inlineTrailingWidth: 140,
    leading: Text(
      '${matchType.label} Summary',
      style: Theme.of(context).textTheme.titleLarge,
    ),
    trailing: _dropdown(expanded: true),
  );
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary, required this.hasGoalkeeperRow});

  final MatchPerformanceSummary summary;
  final bool hasGoalkeeperRow;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final scaledExtent = 80 * textScale;
    return GridView.extent(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      maxCrossAxisExtent: 180,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      mainAxisExtent: scaledExtent < 96 ? 96 : scaledExtent,
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
    );
  }
}

class _MetricSelector extends StatelessWidget {
  const _MetricSelector({required this.value, required this.onChanged});

  final MatchTrendMetric value;
  final ValueChanged<MatchTrendMetric> onChanged;

  Widget _dropdown() => DropdownButtonFormField<MatchTrendMetric>(
    key: const Key('matchesMetricSelector'),
    initialValue: value,
    isExpanded: true,
    decoration: const InputDecoration(
      isDense: true,
      border: OutlineInputBorder(),
    ),
    items: [
      for (final metric in MatchTrendMetric.values)
        DropdownMenuItem(
          value: metric,
          child: Text(metric.label, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (metric) {
      if (metric != null) onChanged(metric);
    },
  );

  @override
  Widget build(BuildContext context) => AdaptiveInlineLayout(
    spacing: 12,
    leading: const Text(
      'Metric:',
      style: TextStyle(fontWeight: FontWeight.w700),
    ),
    trailing: _dropdown(),
  );
}

class _TrendPanel extends StatelessWidget {
  const _TrendPanel({required this.metric, required this.performances});

  final MatchTrendMetric metric;
  final List<MatchPerformance> performances;

  @override
  Widget build(BuildContext context) {
    final chronological = performances.reversed.toList(growable: false);
    final values = chronological.map(metric.valueFor).toList(growable: false);
    if (values.whereType<double>().length < 2) {
      return Card(
        color: AppColors.tealLight,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'There is not enough match data yet to determine a meaningful trend. Complete at least two matches with this metric recorded.',
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: PerformanceTrendChart(
          ratings: values,
          maxValue: metric.maxValueFor(chronological),
          pointLabels: [
            for (final row in chronological)
              '${formatShortDate(row.match.playedOn)} · ${row.match.opponent}',
          ],
          metricLabel: metric.label,
        ),
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
    final passRate = performance.passCompletionRate;
    final feedback = performance.notes.trim();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MatchPerformanceHeader(performance: performance),
            const Divider(height: 24),
            Wrap(
              spacing: 20,
              runSpacing: 12,
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
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.tealLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Coach feedback',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    feedback.isEmpty
                        ? 'No feedback recorded for this match.'
                        : feedback,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchPerformanceHeader extends StatelessWidget {
  const _MatchPerformanceHeader({required this.performance});

  final MatchPerformance performance;

  @override
  Widget build(BuildContext context) {
    final match = performance.match;
    final isTournament = match.category == MatchCategory.tournament;
    return LayoutBuilder(
      builder: (context, constraints) {
        final rating = CircleAvatar(
          backgroundColor: AppColors.tealLight,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              performance.coachRating?.toStringAsFixed(1) ?? '—',
              style: const TextStyle(
                color: AppColors.tealDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        );
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'vs ${match.opponent}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${formatFullDate(match.playedOn)} · ${match.outcome} ${match.scoreLabel}',
            ),
            if (match.competition.trim().isNotEmpty)
              Text(
                match.competition,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        );
        final category = Chip(
          avatar: Icon(
            isTournament
                ? Icons.emoji_events_outlined
                : Icons.sports_soccer_outlined,
            size: 16,
          ),
          label: Text(
            isTournament ? 'Tournament' : 'Regular',
            overflow: TextOverflow.ellipsis,
          ),
          visualDensity: VisualDensity.compact,
        );
        final stacked =
            constraints.maxWidth < 340 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  rating,
                  const SizedBox(width: 12),
                  Expanded(child: details),
                ],
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                child: category,
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            rating,
            const SizedBox(width: 12),
            Expanded(child: details),
            category,
          ],
        );
      },
    );
  }
}

class _InlineStat extends StatelessWidget {
  const _InlineStat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 104,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

class _FilteredMatchesEmptyState extends StatelessWidget {
  const _FilteredMatchesEmptyState({required this.matchType});

  final MatchTypeFilter matchType;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const Icon(Icons.event_busy_outlined, size: 44),
          const SizedBox(height: 12),
          Text(
            'No ${matchType.label.toLowerCase()} recorded yet.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
