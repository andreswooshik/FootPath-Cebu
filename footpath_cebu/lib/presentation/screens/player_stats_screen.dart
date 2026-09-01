import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/player_stats.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/player_stats_providers.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';

class PlayerStatsScreen extends ConsumerWidget {
  const PlayerStatsScreen({
    super.key,
    required this.playerId,
    required this.playerName,
    this.canAssess = false,
  });

  final String playerId;
  final String playerName;
  final bool canAssess;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(playerStatsProvider(playerId));
    return Scaffold(
      appBar: AppBar(title: Text('$playerName · Player Stats')),
      body: stats.when(
        loading: () => const DashboardLoadingState(),
        error: (error, _) => DashboardErrorState(
          message: friendlyErrorMessage(error, 'Could not load Player Stats.'),
          onRetry: () => ref.invalidate(playerStatsProvider(playerId)),
        ),
        data: (data) => _PlayerStatsContent(
          stats: data,
          playerId: playerId,
          playerName: playerName,
          canAssess: canAssess,
        ),
      ),
    );
  }
}

class PlayerStatsSummaryCard extends ConsumerWidget {
  const PlayerStatsSummaryCard({
    super.key,
    required this.playerId,
    required this.onOpen,
  });

  final String playerId;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(playerStatsProvider(playerId));
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: stats.when(
            loading: () => const Row(
              children: [
                SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Loading Player Stats...'),
              ],
            ),
            error: (error, _) => Row(
              children: [
                const Icon(Icons.query_stats_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    friendlyErrorMessage(error, 'Player Stats unavailable.'),
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            data: (data) => _SummaryContent(stats: data),
          ),
        ),
      ),
    );
  }
}

class _SummaryContent extends StatelessWidget {
  const _SummaryContent({required this.stats});

  final PlayerStats stats;

  @override
  Widget build(BuildContext context) {
    final latest = stats.latest;
    final delta = stats.comparison.overallDelta;
    return Row(
      children: [
        CircleAvatar(
          radius: 27,
          child: Text(
            latest?.overall.toString() ?? '—',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Player Stats',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                latest == null
                    ? 'No compatible assessment yet'
                    : '${stats.catalog.position} · ${delta == null ? 'Baseline' : _deltaLabel(delta)}',
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right),
      ],
    );
  }
}

class _PlayerStatsContent extends ConsumerWidget {
  const _PlayerStatsContent({
    required this.stats,
    required this.playerId,
    required this.playerName,
    required this.canAssess,
  });

  final PlayerStats stats;
  final String playerId;
  final String playerName;
  final bool canAssess;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = stats.latest;
    return RefreshIndicator(
      onRefresh: () async {
        await ref
            .read(playerStatsRepositoryProvider)
            .fetchStats(playerId, forceRefresh: true);
        ref.invalidate(playerStatsProvider(playerId));
        await ref.read(playerStatsProvider(playerId).future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _StatsHeader(stats: stats),
          const SizedBox(height: 8),
          const Text(
            'Player Stats are a gamified 0–99 evaluation. They are separate from the formal 1–5 Development Assessment.',
          ),
          if (canAssess) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                final saved = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => PlayerStatsAssessmentScreen(
                      playerId: playerId,
                      playerName: playerName,
                      stats: stats,
                    ),
                  ),
                );
                if (saved == true) {
                  ref.invalidate(playerStatsProvider(playerId));
                }
              },
              icon: const Icon(Icons.add_chart),
              label: const Text('Create Player Stats Assessment'),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Current attributes',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (latest == null)
            const DashboardEmptyState(
              icon: Icons.query_stats_outlined,
              title: 'No Player Stats assessment yet',
              message:
                  'A compatible assessment will appear here when recorded.',
            )
          else
            _AttributeGrid(catalog: stats.catalog, scores: latest.scores),
          if (latest != null && latest.coachNotes.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.notes_outlined),
                title: const Text('Coach notes'),
                subtitle: Text(latest.coachNotes),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            'Assessment history',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (stats.history.isEmpty)
            const Text('No compatible Player Stats history yet.')
          else
            for (final assessment in stats.history)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(child: Text('${assessment.overall}')),
                  title: Text(_reasonLabel(assessment.reason)),
                  subtitle: Text(
                    '${formatFullDate(assessment.createdAt)} · ${assessment.assessedBy ?? 'Coach'}\n${assessment.coachNotes}',
                  ),
                  isThreeLine: true,
                  trailing: Text(assessment.position),
                ),
              ),
          if (stats.legacyHistory.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${stats.legacyHistory.length} legacy rating records are kept separately.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class PlayerStatsAssessmentScreen extends ConsumerStatefulWidget {
  const PlayerStatsAssessmentScreen({
    super.key,
    required this.playerId,
    required this.playerName,
    required this.stats,
  });
  final String playerId;
  final String playerName;
  final PlayerStats stats;

  @override
  ConsumerState<PlayerStatsAssessmentScreen> createState() =>
      _PlayerStatsAssessmentScreenState();
}

class _PlayerStatsAssessmentScreenState
    extends ConsumerState<PlayerStatsAssessmentScreen> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _scores = {
    for (final attribute in widget.stats.catalog.attributes)
      _scoreKey(attribute): TextEditingController(),
  };
  final _notes = TextEditingController();
  String _reason = 'GENERAL_REVIEW';
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in _scores.values) {
      controller.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  Map<String, int> get _values => _scores.map(
    (key, controller) => MapEntry(key, int.parse(controller.text)),
  );
  int get _overall => (_values.values.reduce((a, b) => a + b) / 6).round();

  Future<void> _preview() async {
    if (!_formKey.currentState!.validate()) return;
    final values = _values;
    final previous = widget.stats.latest;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Player Stats'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.playerName} · ${widget.stats.catalog.position}'),
              const SizedBox(height: 12),
              for (final attribute in widget.stats.catalog.attributes)
                _PreviewRow(
                  label: attribute,
                  previous: previous?.scores[_scoreKey(attribute)],
                  current: values[_scoreKey(attribute)]!,
                ),
              const Divider(),
              _PreviewRow(
                label: 'Overall',
                previous: previous?.overall,
                current: _overall,
              ),
              const SizedBox(height: 8),
              Text(
                previous == null
                    ? 'This is a new baseline.'
                    : 'Changes are calculated automatically.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Review'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save Assessment'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _save(values);
  }

  Future<void> _save(Map<String, int> values) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(playerStatsRepositoryProvider)
          .saveAssessment(
            widget.playerId,
            PlayerStatsDraft(
              catalogVersion: widget.stats.catalog.version,
              scores: values,
              reason: _reason,
              coachNotes: _notes.text.trim(),
            ),
          );
      ref.invalidate(playerStatsProvider(widget.playerId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Player Stats assessment saved.')),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(error, 'Could not save Player Stats.'),
          ),
        ),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New Player Stats Assessment')),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.all(16),
      child: FilledButton.icon(
        onPressed: _saving ? null : _preview,
        icon: _saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.preview_outlined),
        label: Text(_saving ? 'Saving…' : 'Review and Save'),
      ),
    ),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Enter a fresh 0–99 score for every attribute. Previous values are shown below only for comparison and never prefilled.',
          ),
          if (widget.stats.latest != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Previous assessment',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Overall ${widget.stats.latest!.overall} · ${formatFullDate(widget.stats.latest!.createdAt)}',
                    ),
                    Wrap(
                      spacing: 12,
                      children: [
                        for (final attribute in widget.stats.catalog.attributes)
                          Text(
                            '$attribute ${widget.stats.latest!.scores[_scoreKey(attribute)]}',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          for (final attribute in widget.stats.catalog.attributes) ...[
            TextFormField(
              controller: _scores[_scoreKey(attribute)],
              decoration: InputDecoration(
                labelText: '$attribute *',
                hintText: '0–99',
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              validator: (text) {
                final value = int.tryParse(text ?? '');
                if (value == null) return '$attribute is required.';
                if (value < 0 || value > 99) {
                  return 'Enter a value from 0 to 99.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<String>(
            initialValue: _reason,
            decoration: const InputDecoration(
              labelText: 'Assessment reason *',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'GENERAL_REVIEW',
                child: Text('General review'),
              ),
              DropdownMenuItem(
                value: 'MONTHLY_REVIEW',
                child: Text('Monthly review'),
              ),
              DropdownMenuItem(
                value: 'POST_TOURNAMENT',
                child: Text('Post-tournament'),
              ),
              DropdownMenuItem(
                value: 'RETURN_FROM_INJURY',
                child: Text('Return from injury'),
              ),
              DropdownMenuItem(value: 'OTHER', child: Text('Other')),
            ],
            onChanged: (value) => _reason = value!,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notes,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Coach notes *',
              border: OutlineInputBorder(),
            ),
            validator: (text) => (text ?? '').trim().isEmpty
                ? 'Coach notes are required.'
                : null,
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.label,
    required this.previous,
    required this.current,
  });
  final String label;
  final int? previous;
  final int current;
  @override
  Widget build(BuildContext context) {
    final delta = previous == null ? null : current - previous!;
    final color = delta == null || delta == 0
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : delta > 0
        ? Colors.green
        : Colors.red;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text('${previous ?? '—'} → $current  '),
          Text(
            delta == null
                ? 'Baseline'
                : delta == 0
                ? '0'
                : '${delta > 0 ? '+' : ''}$delta',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _StatsHeader extends StatelessWidget {
  const _StatsHeader({required this.stats});

  final PlayerStats stats;

  @override
  Widget build(BuildContext context) {
    final latest = stats.latest;
    final delta = stats.comparison.overallDelta;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(
            latest?.overall.toString() ?? '—',
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${stats.catalog.roleGroup} · ${stats.catalog.position}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  delta == null ? 'Baseline not recorded' : _deltaLabel(delta),
                ),
                if (latest != null)
                  Text(
                    'Updated ${formatFullDate(latest.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttributeGrid extends StatelessWidget {
  const _AttributeGrid({required this.catalog, required this.scores});

  final PlayerStatsCatalog catalog;
  final Map<String, int> scores;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final attribute in catalog.attributes)
        SizedBox(
          width: 106,
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Column(
                children: [
                  Text(
                    '${scores[_scoreKey(attribute)] ?? 0}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(attribute, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

String _scoreKey(String attribute) =>
    attribute.toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');

String _deltaLabel(int delta) => delta == 0
    ? 'No change'
    : '${delta > 0 ? '+' : ''}$delta overall since previous assessment';

String _reasonLabel(String reason) => reason
    .toLowerCase()
    .split('_')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');
