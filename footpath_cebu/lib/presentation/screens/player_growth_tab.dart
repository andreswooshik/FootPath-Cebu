import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/match_performance.dart';
import 'package:footpath_cebu/domain/entities/player_growth.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/growth_providers.dart';
import 'package:footpath_cebu/presentation/theme/app_theme.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/match_trend_metric.dart';
import 'package:footpath_cebu/presentation/widgets/match_type_filter.dart';
import 'package:footpath_cebu/presentation/widgets/performance_trend_chart.dart';

/// Long-term match development summary embedded in the player's Progress tab.
/// It intentionally compares matches instead of repeating the full history.
class PlayerGrowthTab extends ConsumerStatefulWidget {
  const PlayerGrowthTab({
    super.key,
    required this.playerId,
    required this.playerName,
  });

  final String playerId;
  final String playerName;

  @override
  ConsumerState<PlayerGrowthTab> createState() => _PlayerGrowthTabState();
}

class _PlayerGrowthTabState extends ConsumerState<PlayerGrowthTab> {
  GrowthRange _range = GrowthRange.last10;
  MatchTypeFilter _matchType = MatchTypeFilter.all;
  MatchTrendMetric _metric = MatchTrendMetric.rating;

  GrowthQuery get _query => GrowthQuery(
    playerId: widget.playerId,
    range: _range,
    category: GrowthCategory.all,
  );

  @override
  Widget build(BuildContext context) {
    final growth = ref.watch(playerGrowthProvider(_query));
    return growth.when(
      loading: () => const DashboardLoadingState(),
      error: (error, _) => DashboardErrorState(
        message: friendlyErrorMessage(error, 'Could not load player growth.'),
        onRetry: () => ref.invalidate(playerGrowthProvider(_query)),
      ),
      data: _buildGrowth,
    );
  }

  Widget _buildGrowth(PlayerGrowth growth) {
    final rows = _filteredRows(growth, _matchType);
    final chronological = [...rows]
      ..sort((a, b) => a.match.playedOn.compareTo(b.match.playedOn));
    final latestAssessment = growth.developmentAssessments.isEmpty
        ? null
        : ([
            ...growth.developmentAssessments,
          ]..sort((a, b) => b.createdAt.compareTo(a.createdAt))).first;

    return RefreshIndicator(
      onRefresh: () => ref.refresh(playerGrowthProvider(_query).future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Growth',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    'Understand how ${widget.playerName} is developing across multiple matches.',
                  ),
                ],
              ),
              DropdownButton<GrowthRange>(
                key: const Key('growthRangeSelector'),
                value: _range,
                borderRadius: BorderRadius.circular(14),
                items: [
                  for (final range in GrowthRange.values)
                    DropdownMenuItem(value: range, child: Text(range.label)),
                ],
                onChanged: (range) {
                  if (range != null) setState(() => _range = range);
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          MatchTypeFilterBar(
            selected: _matchType,
            onSelected: (value) => setState(() => _matchType = value),
          ),
          const SizedBox(height: 16),
          _OverallGrowthCard(rows: chronological, matchType: _matchType),
          const SizedBox(height: 12),
          _DevelopmentFocusCards(
            rows: chronological,
            assessmentStrength: latestAssessment?.strengths ?? '',
            assessmentTarget: latestAssessment?.developmentTargets ?? '',
          ),
          const SizedBox(height: 12),
          _ThenVsNowCard(rows: chronological),
          const SizedBox(height: 20),
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
          _GrowthMetricSelector(
            value: _metric,
            onChanged: (value) => setState(() => _metric = value),
          ),
          const SizedBox(height: 8),
          _GrowthTrendPanel(metric: _metric, rows: chronological),
          const SizedBox(height: 12),
          _RecommendationsCard(
            rows: chronological,
            assessmentTarget: latestAssessment?.developmentTargets ?? '',
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

List<MatchPerformance> _filteredRows(
  PlayerGrowth growth,
  MatchTypeFilter filter,
) {
  final regular = growth.regularMatches?.history ?? const <MatchPerformance>[];
  final tournaments = growth.tournaments
      .expand((group) => group.history)
      .toList(growable: false);
  final selected = switch (filter) {
    MatchTypeFilter.all => [...regular, ...tournaments],
    MatchTypeFilter.regular => [...regular],
    MatchTypeFilter.tournaments => [...tournaments],
  };
  // A performance can appear in more than one aggregate in malformed or old
  // responses. Keep one copy so the comparison is never double-counted.
  return {
    for (final row in selected) row.id: row,
  }.values.toList(growable: false);
}

class _OverallGrowthCard extends StatelessWidget {
  const _OverallGrowthCard({required this.rows, required this.matchType});

  final List<MatchPerformance> rows;
  final MatchTypeFilter matchType;

  @override
  Widget build(BuildContext context) {
    final comparison = _comparison(rows, MatchTrendMetric.rating);
    final improving = comparison.delta != null && comparison.delta! > 0.15;
    final declining = comparison.delta != null && comparison.delta! < -0.15;
    final label = rows.length < 2
        ? 'More data needed'
        : improving
        ? 'Improving'
        : declining
        ? 'Needs attention'
        : 'Holding steady';
    final color = rows.length < 2
        ? Colors.blueGrey
        : improving
        ? AppColors.tealDark
        : declining
        ? Theme.of(context).colorScheme.error
        : Colors.blueGrey;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Overall growth summary',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(
                  label: Text(label),
                  labelStyle: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                  backgroundColor: color.withValues(alpha: 0.10),
                  side: BorderSide(color: color.withValues(alpha: 0.4)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_matchCountLabel(rows.length, matchType)} included in this comparison.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _SummaryValue(
                  label: 'Earlier rating',
                  value: _formatValue(comparison.thenValue),
                ),
                _SummaryValue(
                  label: 'Recent rating',
                  value: _formatValue(comparison.nowValue),
                ),
                _SummaryValue(
                  label: 'Change',
                  value: _formatDelta(comparison.delta),
                  color: color,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DevelopmentFocusCards extends StatelessWidget {
  const _DevelopmentFocusCards({
    required this.rows,
    required this.assessmentStrength,
    required this.assessmentTarget,
  });

  final List<MatchPerformance> rows;
  final String assessmentStrength;
  final String assessmentTarget;

  @override
  Widget build(BuildContext context) {
    final derived = [
      for (final metric in MatchTrendMetric.values)
        (metric: metric, comparison: _comparison(rows, metric)),
    ];
    derived.sort(
      (a, b) => (b.comparison.delta ?? -double.infinity).compareTo(
        a.comparison.delta ?? -double.infinity,
      ),
    );
    final strongest = derived.where((item) => (item.comparison.delta ?? 0) > 0);
    final weakest = derived.reversed.where(
      (item) => (item.comparison.delta ?? 0) <= 0,
    );
    final strength = assessmentStrength.trim().isNotEmpty
        ? assessmentStrength.trim()
        : strongest.isNotEmpty
        ? '${strongest.first.metric.label} has improved by ${_formatDelta(strongest.first.comparison.delta)}.'
        : 'Complete more rated matches to identify a consistent strength.';
    final target = assessmentTarget.trim().isNotEmpty
        ? assessmentTarget.trim()
        : weakest.isNotEmpty
        ? 'Focus on ${weakest.first.metric.label.toLowerCase()} in the next training block.'
        : 'Keep building consistency across the selected matches.';

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 680;
        final cards = [
          _FocusCard(
            icon: Icons.check_circle_outline,
            title: 'Current strengths',
            body: strength,
            color: AppColors.tealDark,
          ),
          _FocusCard(
            icon: Icons.flag_outlined,
            title: 'Skills to improve',
            body: target,
            color: AppColors.coral,
          ),
        ];
        if (!wide) {
          return Column(
            children: [cards.first, const SizedBox(height: 12), cards.last],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cards.first),
            const SizedBox(width: 12),
            Expanded(child: cards.last),
          ],
        );
      },
    );
  }
}

class _FocusCard extends StatelessWidget {
  const _FocusCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(body),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ThenVsNowCard extends StatelessWidget {
  const _ThenVsNowCard({required this.rows});

  final List<MatchPerformance> rows;

  @override
  Widget build(BuildContext context) {
    final hasComparison = rows.length >= 2;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Then vs. Now', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              hasComparison
                  ? '${formatFullDate(rows.first.match.playedOn)} compared with ${formatFullDate(rows.last.match.playedOn)}'
                  : 'At least two matches are needed for a meaningful comparison.',
            ),
            if (hasComparison) ...[
              const SizedBox(height: 14),
              for (final metric in MatchTrendMetric.values)
                _ComparisonRow(
                  metric: metric,
                  comparison: _comparison(rows, metric),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({required this.metric, required this.comparison});

  final MatchTrendMetric metric;
  final _MetricComparison comparison;

  @override
  Widget build(BuildContext context) {
    final delta = comparison.delta;
    final color = delta == null || delta == 0
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : delta > 0
        ? AppColors.tealDark
        : Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(metric.label)),
          Expanded(
            child: Text(
              _formatMetricValue(metric, comparison.thenValue),
              textAlign: TextAlign.end,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward, size: 16),
          ),
          Expanded(
            child: Text(
              _formatMetricValue(metric, comparison.nowValue),
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              _formatDelta(delta, unit: metric.unit),
              textAlign: TextAlign.end,
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _GrowthMetricSelector extends StatelessWidget {
  const _GrowthMetricSelector({required this.value, required this.onChanged});

  final MatchTrendMetric value;
  final ValueChanged<MatchTrendMetric> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Text('Metric:', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(width: 12),
      Expanded(
        child: DropdownButtonFormField<MatchTrendMetric>(
          key: const Key('growthMetricSelector'),
          initialValue: value,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final metric in MatchTrendMetric.values)
              DropdownMenuItem(value: metric, child: Text(metric.label)),
          ],
          onChanged: (metric) {
            if (metric != null) onChanged(metric);
          },
        ),
      ),
    ],
  );
}

class _GrowthTrendPanel extends StatelessWidget {
  const _GrowthTrendPanel({required this.metric, required this.rows});

  final MatchTrendMetric metric;
  final List<MatchPerformance> rows;

  @override
  Widget build(BuildContext context) {
    final values = rows.map(metric.valueFor).toList(growable: false);
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
                  'There is not enough data to determine a meaningful trend for this metric. Add at least two comparable matches.',
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
          maxValue: metric.maxValueFor(rows),
          pointLabels: [
            for (final row in rows)
              '${formatShortDate(row.match.playedOn)} · ${row.match.opponent}',
          ],
          metricLabel: metric.label,
        ),
      ),
    );
  }
}

class _RecommendationsCard extends StatelessWidget {
  const _RecommendationsCard({
    required this.rows,
    required this.assessmentTarget,
  });

  final List<MatchPerformance> rows;
  final String assessmentTarget;

  @override
  Widget build(BuildContext context) {
    final recommendations = <String>[];
    if (assessmentTarget.trim().isNotEmpty) {
      recommendations.add(assessmentTarget.trim());
    }
    if (rows.length >= 2) {
      final passing = _comparison(rows, MatchTrendMetric.passing);
      final rating = _comparison(rows, MatchTrendMetric.rating);
      final goals = _comparison(rows, MatchTrendMetric.goals);
      if ((passing.nowValue ?? 100) < 75 || (passing.delta ?? 0) < 0) {
        recommendations.add(
          'Prioritize first-touch and passing-under-pressure drills in the next training block.',
        );
      }
      if ((rating.delta ?? 0) < 0) {
        recommendations.add(
          'Review recent coach feedback and agree on one match objective before the next fixture.',
        );
      }
      if ((goals.delta ?? 0) <= 0) {
        recommendations.add(
          'Add finishing and off-ball movement repetitions, then track the result over the next two matches.',
        );
      }
    }
    if (recommendations.isEmpty) {
      recommendations.add(
        rows.length < 2
            ? 'Record at least two comparable matches before setting a data-based training target.'
            : 'Maintain the current plan and set one measurable focus for the next two matches.',
      );
    }
    return Card(
      color: AppColors.tealLight,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lightbulb_outline, color: AppColors.tealDark),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Actionable training recommendations',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final recommendation in recommendations.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '•  ',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Expanded(child: Text(recommendation)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      Text(
        value,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color),
      ),
    ],
  );
}

class _MetricComparison {
  const _MetricComparison(this.thenValue, this.nowValue);

  final double? thenValue;
  final double? nowValue;

  double? get delta =>
      thenValue == null || nowValue == null ? null : nowValue! - thenValue!;
}

_MetricComparison _comparison(
  List<MatchPerformance> chronological,
  MatchTrendMetric metric,
) {
  if (chronological.length < 2) return const _MetricComparison(null, null);
  return _MetricComparison(
    metric.valueFor(chronological.first),
    metric.valueFor(chronological.last),
  );
}

String _formatValue(double? value) => value?.toStringAsFixed(1) ?? '—';

String _matchCountLabel(int count, MatchTypeFilter filter) {
  final noun = switch (filter) {
    MatchTypeFilter.all => 'match',
    MatchTypeFilter.regular => 'regular match',
    MatchTypeFilter.tournaments => 'tournament match',
  };
  return '$count $noun${count == 1 ? '' : 'es'}';
}

String _formatMetricValue(MatchTrendMetric metric, double? value) {
  if (value == null) return '—';
  final formatted =
      metric == MatchTrendMetric.rating || metric == MatchTrendMetric.passing
      ? value.toStringAsFixed(1)
      : value.toStringAsFixed(0);
  return '$formatted${metric.unit}';
}

String _formatDelta(double? value, {String unit = ''}) {
  if (value == null) return '—';
  final prefix = value > 0 ? '+' : '';
  return '$prefix${value.toStringAsFixed(1)}$unit';
}
