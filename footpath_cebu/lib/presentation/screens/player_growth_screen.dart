import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/match_performance.dart';
import 'package:footpath_cebu/domain/entities/player_growth.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/growth_providers.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/performance_trend_chart.dart';

class PlayerGrowthScreen extends ConsumerStatefulWidget {
  const PlayerGrowthScreen({
    super.key,
    required this.playerId,
    required this.playerName,
  });

  final String playerId;
  final String playerName;

  @override
  ConsumerState<PlayerGrowthScreen> createState() => _PlayerGrowthScreenState();
}

class _PlayerGrowthScreenState extends ConsumerState<PlayerGrowthScreen> {
  GrowthRange _range = GrowthRange.last10;

  GrowthQuery get _query =>
      GrowthQuery(playerId: widget.playerId, range: _range);

  @override
  Widget build(BuildContext context) {
    final growth = ref.watch(playerGrowthProvider(_query));
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.playerName} · Growth'),
          actions: [
            PopupMenuButton<GrowthRange>(
              tooltip: 'Growth range',
              initialValue: _range,
              onSelected: (range) => setState(() => _range = range),
              itemBuilder: (context) => [
                for (final range in GrowthRange.values)
                  PopupMenuItem(value: range, child: Text(range.label)),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.date_range_outlined, size: 18),
                    const SizedBox(width: 6),
                    Text(_range.label),
                  ],
                ),
              ),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Assessments'),
              Tab(text: 'Training'),
              Tab(text: 'Matches'),
              Tab(text: 'Tournaments'),
            ],
          ),
        ),
        body: growth.when(
          loading: () => const DashboardLoadingState(),
          error: (error, _) => DashboardErrorState(
            message: friendlyErrorMessage(
              error,
              'Could not load categorized player growth.',
            ),
            onRetry: () => ref.invalidate(playerGrowthProvider(_query)),
          ),
          data: (data) => TabBarView(
            children: [
              _OverviewTab(growth: data, range: _range),
              _AssessmentsTab(growth: data),
              _TrainingTab(groups: data.training),
              _MatchesTab(growth: data.regularMatches, position: data.position),
              _TournamentsTab(groups: data.tournaments),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.growth, required this.range});

  final PlayerGrowth growth;
  final GrowthRange range;

  @override
  Widget build(BuildContext context) {
    final assessment = growth.assessmentSummary;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${range.label} overview',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        const Text(
          'Each category keeps its own scale. Assessment, effort, training quality, and match rates are never mixed into one unexplained score.',
        ),
        const SizedBox(height: 16),
        _TrendCard(
          title: 'Performance assessments',
          value: assessment?.latestOverall?.toString() ?? '—',
          detail: assessment == null
              ? 'No assessment data'
              : '${assessment.sampleSize} snapshots · ${_delta(assessment.overallDelta)} overall',
          classification:
              assessment?.classification ??
              GrowthClassification.insufficientData,
        ),
        for (final group in growth.training)
          _TrendCard(
            title: '${_title(group.focus)} training',
            value: group.averagePerformanceScore?.toStringAsFixed(1) ?? '—',
            detail:
                '${group.sampleSize} sessions · ${group.averageEffort?.toStringAsFixed(0) ?? '—'}% effort',
            classification: group.classification,
          ),
        _TrendCard(
          title: 'Regular matches',
          value:
              growth.regularMatches?.summary.averageRating?.toStringAsFixed(
                1,
              ) ??
              '—',
          detail:
              '${growth.regularMatches?.sampleSize ?? 0} played · coach rating',
          classification: _representativeMatchTrend(growth.regularMatches),
        ),
        _TrendCard(
          title: 'Tournament matches',
          value:
              '${growth.tournaments.fold<int>(0, (sum, group) => sum + group.sampleSize)}',
          detail: '${growth.tournaments.length} tournament/age-bracket groups',
          classification: growth.tournaments.isEmpty
              ? GrowthClassification.insufficientData
              : GrowthClassification.stable,
        ),
      ],
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.title,
    required this.value,
    required this.detail,
    required this.classification,
  });

  final String title;
  final String value;
  final String detail;
  final GrowthClassification classification;

  @override
  Widget build(BuildContext context) {
    final color = _classificationColor(context, classification);
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(detail),
        leading: CircleAvatar(child: Text(value)),
        trailing: Chip(
          label: Text(classification.label),
          backgroundColor: color.withValues(alpha: 0.12),
          side: BorderSide(color: color),
        ),
      ),
    );
  }
}

class _AssessmentsTab extends StatelessWidget {
  const _AssessmentsTab({required this.growth});

  final PlayerGrowth growth;

  @override
  Widget build(BuildContext context) {
    final rows = growth.assessments;
    if (rows.isEmpty) {
      return const DashboardEmptyState(
        icon: Icons.assessment_outlined,
        title: 'No assessment history',
        message: 'A baseline or coach review will appear here when recorded.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final previous = index + 1 < rows.length ? rows[index + 1] : null;
        return Card(
          child: ExpansionTile(
            leading: CircleAvatar(child: Text('${row.overall}')),
            title: Text(row.reason.label),
            subtitle: Text(
              '${formatFullDate(row.createdAt)} · ${row.position.isEmpty ? 'No position' : row.position}',
            ),
            trailing: Text(
              previous == null
                  ? 'Baseline'
                  : _delta(row.overall - previous.overall),
              style: TextStyle(
                color: _deltaColor(
                  context,
                  previous == null ? 0 : row.overall - previous.overall,
                ),
                fontWeight: FontWeight.w800,
              ),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(row.coachNotes.isEmpty ? 'No coach notes.' : row.coachNotes),
              const SizedBox(height: 8),
              Text('Sample ${rows.length} · position-aware overall'),
            ],
          ),
        );
      },
    );
  }
}

class _TrainingTab extends StatelessWidget {
  const _TrainingTab({required this.groups});

  final List<TrainingGrowthGroup> groups;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [for (final group in groups) _TrainingGroupCard(group: group)],
  );
}

class _TrainingGroupCard extends StatelessWidget {
  const _TrainingGroupCard({required this.group});

  final TrainingGrowthGroup group;

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      title: Text('${_title(group.focus)} Training'),
      subtitle: Text(
        '${group.sampleSize} sessions · ${group.presentCount} present · '
        '${group.attendanceRate?.toStringAsFixed(0) ?? '—'}% attendance',
      ),
      trailing: Chip(label: Text(group.classification.label)),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            _InlineValue(
              'Avg effort',
              group.averageEffort == null
                  ? '—'
                  : '${group.averageEffort!.toStringAsFixed(0)}%',
            ),
            _InlineValue(
              'Avg performance',
              group.averagePerformanceScore?.toStringAsFixed(1) ?? '—',
            ),
            _InlineValue(
              'Quality change',
              _decimalDelta(group.performanceDelta),
            ),
            _InlineValue('Effort change', _decimalDelta(group.effortDelta)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Comparison (${group.comparisonMetric == 'EFFORT' ? 'effort' : 'performance score'}): '
          '${group.recentSampleSize} recent vs ${group.previousSampleSize} previous',
        ),
        if (group.history.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('No individual session results in this range.'),
          )
        else
          for (final row in group.history) _TrainingResult(row: row),
      ],
    ),
  );
}

class _TrainingResult extends StatelessWidget {
  const _TrainingResult({required this.row});
  final Attendance row;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(row.sessionName ?? 'Training session'),
    subtitle: Text(
      '${formatShortDate(row.sessionDate ?? row.updatedAt)} · ${row.status.label}${(row.note ?? '').isEmpty ? '' : ' · ${row.note}'}',
    ),
    trailing: Text(
      row.performanceScore == null
          ? row.effort == null
                ? '—'
                : '${row.effort}% effort'
          : '${row.performanceScore!.toStringAsFixed(1)}/10',
    ),
  );
}

enum _MatchMetric {
  coachRating,
  goalsPer90,
  assistsPer90,
  passCompletion,
  shotsOnTarget,
  tacklesInterceptionsPer90,
  savesPer90,
  goalsConcededPer90,
}

extension on _MatchMetric {
  String get label => switch (this) {
    _MatchMetric.coachRating => 'Coach rating',
    _MatchMetric.goalsPer90 => 'Goals per 90',
    _MatchMetric.assistsPer90 => 'Assists per 90',
    _MatchMetric.passCompletion => 'Pass completion',
    _MatchMetric.shotsOnTarget => 'Shots on target',
    _MatchMetric.tacklesInterceptionsPer90 => 'Tackles + interceptions per 90',
    _MatchMetric.savesPer90 => 'Saves per 90',
    _MatchMetric.goalsConcededPer90 => 'Goals conceded per 90',
  };
}

class _MatchesTab extends StatefulWidget {
  const _MatchesTab({required this.growth, required this.position});
  final MatchGrowth? growth;
  final String position;

  @override
  State<_MatchesTab> createState() => _MatchesTabState();
}

class _MatchesTabState extends State<_MatchesTab> {
  _MatchMetric _metric = _MatchMetric.coachRating;

  @override
  Widget build(BuildContext context) {
    final growth = widget.growth;
    if (growth == null || growth.history.isEmpty) {
      return const DashboardEmptyState(
        icon: Icons.sports_soccer_outlined,
        title: 'No regular-match history',
        message: 'Tournament matches are kept in their own category.',
      );
    }
    final metrics = widget.position == 'GK'
        ? const [
            _MatchMetric.coachRating,
            _MatchMetric.passCompletion,
            _MatchMetric.savesPer90,
            _MatchMetric.goalsConcededPer90,
          ]
        : const [
            _MatchMetric.coachRating,
            _MatchMetric.goalsPer90,
            _MatchMetric.assistsPer90,
            _MatchMetric.passCompletion,
            _MatchMetric.shotsOnTarget,
            _MatchMetric.tacklesInterceptionsPer90,
          ];
    if (!metrics.contains(_metric)) _metric = metrics.first;
    final chronological = growth.history.reversed.toList(growable: false);
    final values = chronological
        .map((row) => _metricValue(row, _metric))
        .toList();
    final maxValue =
        _metric == _MatchMetric.passCompletion ||
            _metric == _MatchMetric.shotsOnTarget
        ? 100.0
        : _metric == _MatchMetric.coachRating
        ? 10.0
        : (values.whereType<double>().fold<double>(
                1,
                (max, value) => value > max ? value : max,
              ) *
              1.2);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Regular matches · ${growth.sampleSize} samples',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            DropdownButton<_MatchMetric>(
              value: _metric,
              items: [
                for (final metric in metrics)
                  DropdownMenuItem(value: metric, child: Text(metric.label)),
              ],
              onChanged: (metric) {
                if (metric != null) setState(() => _metric = metric);
              },
            ),
          ],
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: PerformanceTrendChart(
              ratings: values,
              maxValue: maxValue,
              pointLabels: [
                for (final row in chronological)
                  formatShortDate(row.match.playedOn),
              ],
              metricLabel: _metric.label,
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final row in growth.history)
          Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text(row.coachRating?.toStringAsFixed(1) ?? '—'),
              ),
              title: Text('vs ${row.match.opponent} · ${row.match.scoreLabel}'),
              subtitle: Text(
                '${formatShortDate(row.match.playedOn)} · ${row.match.category.label} · ${row.minutesPlayed} min',
              ),
              trailing: Chip(
                label: Text(row.coachRating == null ? 'Not rated' : 'Rated'),
              ),
            ),
          ),
      ],
    );
  }
}

class _TournamentsTab extends StatelessWidget {
  const _TournamentsTab({required this.groups});
  final List<TournamentGrowthGroup> groups;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const DashboardEmptyState(
        icon: Icons.emoji_events_outlined,
        title: 'No tournament performance yet',
        message:
            'Only fixtures with this player’s performance row count as played.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final group in groups)
          Card(
            child: ExpansionTile(
              leading: const CircleAvatar(
                child: Icon(Icons.emoji_events_outlined),
              ),
              title: Text(group.tournament),
              subtitle: Text(
                '${group.ageBracketLabel ?? 'Open age'} · ${group.sampleSize} player fixtures',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Team record for player fixtures: ${group.wins}W ${group.draws}D ${group.losses}L',
                ),
                Text(
                  '${group.summary.minutesPlayed} minutes · ${group.summary.goals} goals · ${group.summary.assists} assists',
                ),
                Text(
                  'Pass completion ${group.summary.passCompletionRate?.toStringAsFixed(1) ?? '—'}% · Coach rating ${group.summary.averageRating?.toStringAsFixed(1) ?? '—'}',
                ),
                const Divider(),
                for (final row in group.history)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${row.match.outcome} · ${row.match.scoreLabel} vs ${row.match.opponent}',
                    ),
                    subtitle: Text(
                      '${formatShortDate(row.match.playedOn)} · ${row.match.ageBracketLabel ?? 'Tournament'} · ${row.minutesPlayed} min',
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _InlineValue extends StatelessWidget {
  const _InlineValue(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelSmall),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
    ],
  );
}

double? _metricValue(MatchPerformance row, _MatchMetric metric) {
  double? per90(int value) =>
      row.minutesPlayed == 0 ? null : value * 90 / row.minutesPlayed;
  return switch (metric) {
    _MatchMetric.coachRating => row.coachRating,
    _MatchMetric.goalsPer90 => per90(row.goals),
    _MatchMetric.assistsPer90 => per90(row.assists),
    _MatchMetric.passCompletion => row.passCompletionRate,
    _MatchMetric.shotsOnTarget =>
      row.shots == 0 ? null : row.shotsOnTarget * 100 / row.shots,
    _MatchMetric.tacklesInterceptionsPer90 => per90(
      row.tackles + row.interceptions,
    ),
    _MatchMetric.savesPer90 => per90(row.saves),
    _MatchMetric.goalsConcededPer90 => per90(row.goalsConceded),
  };
}

GrowthClassification _representativeMatchTrend(MatchGrowth? growth) {
  if (growth == null) return GrowthClassification.insufficientData;
  return growth.metrics['averageRating']?.classification ??
      growth.metrics['goalsPer90']?.classification ??
      GrowthClassification.insufficientData;
}

String _title(String value) =>
    value.isEmpty ? value : '${value[0]}${value.substring(1).toLowerCase()}';

String _delta(int? value) => value == null
    ? '—'
    : value > 0
    ? '+$value'
    : '$value';
String _decimalDelta(double? value) => value == null
    ? '—'
    : value > 0
    ? '+${value.toStringAsFixed(1)}'
    : value.toStringAsFixed(1);

Color _deltaColor(BuildContext context, int value) {
  if (value > 0) return Colors.green.shade700;
  if (value < 0) return Theme.of(context).colorScheme.error;
  return Theme.of(context).colorScheme.onSurfaceVariant;
}

Color _classificationColor(
  BuildContext context,
  GrowthClassification classification,
) => switch (classification) {
  GrowthClassification.improving => Colors.green.shade700,
  GrowthClassification.stable => Colors.blueGrey,
  GrowthClassification.needsAttention => Theme.of(context).colorScheme.error,
  GrowthClassification.insufficientData => Colors.grey.shade600,
};
