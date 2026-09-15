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
                final saved = await Navigator.of(context)
                    .push<PlayerStatsSaveResult>(
                      MaterialPageRoute(
                        builder: (_) => PlayerStatsAssessmentScreen(
                          playerId: playerId,
                          playerName: playerName,
                          stats: stats,
                        ),
                      ),
                    );
                if (saved != null) {
                  ref.invalidate(playerStatsProvider(playerId));
                }
              },
              icon: const Icon(Icons.add_chart),
              label: Text(
                latest == null
                    ? 'Create Player Stats baseline'
                    : 'Update player attributes',
              ),
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
          if (stats.history.length > 1) ...[
            const SizedBox(height: 16),
            Text(
              'Overall trend',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 150,
              child: _TrendChart(assessments: stats.history),
            ),
          ],
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
            for (var index = 0; index < stats.history.length; index++)
              _HistoryCard(
                assessment: stats.history[index],
                previous: index + 1 < stats.history.length
                    ? stats.history[index + 1]
                    : null,
                attributes: stats.catalog.attributes,
              ),
          if (stats.legacyHistory.isNotEmpty) ...[
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: ExpansionTile(
                title: const Text('Legacy Stats History'),
                subtitle: const Text('Read-only FIFA-style ratings'),
                children: [
                  for (final record in stats.legacyHistory)
                    ListTile(
                      leading: CircleAvatar(child: Text('${record.overall}')),
                      title: Text(
                        '${record.position} · ${_reasonLabel(record.reason)}',
                      ),
                      subtitle: Text(
                        '${formatFullDate(record.createdAt)} · ${record.assessedByRole ?? 'Coach'}\n'
                        '${record.ratings.entries.map((entry) => '${entry.key}: ${entry.value}').join(' · ')}\n'
                        '${record.coachNotes}',
                      ),
                      isThreeLine: true,
                    ),
                ],
              ),
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
  final _attributesFormKey = GlobalKey<FormState>();
  final _contextFormKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _scores = {
    for (final attribute in widget.stats.catalog.attributes)
      _scoreKey(attribute): TextEditingController(
        text:
            widget.stats.latest?.scores[_scoreKey(attribute)]?.toString() ?? '',
      ),
  };
  final _notes = TextEditingController();
  String? _reason;
  int _step = 0;
  bool _saving = false;
  String? _saveError;

  @override
  void dispose() {
    for (final controller in _scores.values) {
      controller.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  Map<String, int> get _values => _scores.map(
    (key, controller) => MapEntry(key, int.parse(controller.text.trim())),
  );
  int get _overall => (_values.values.reduce((a, b) => a + b) / 6).round();
  bool get _hasChanges {
    final previous = widget.stats.latest;
    if (previous == null) return true;
    return _scores.entries.any(
      (entry) =>
          int.tryParse(entry.value.text.trim()) != previous.scores[entry.key],
    );
  }

  void _continue() {
    FocusScope.of(context).unfocus();
    if (_step == 0) {
      if (!(_attributesFormKey.currentState?.validate() ?? false)) return;
      setState(() => _step = 1);
      return;
    }
    if (_step == 1) {
      if (!(_contextFormKey.currentState?.validate() ?? false)) return;
      setState(() => _step = 2);
    }
  }

  Future<void> _save() async {
    if (_saving || !_hasChanges) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final result = await ref
          .read(playerStatsRepositoryProvider)
          .saveAssessment(
            widget.playerId,
            PlayerStatsDraft(
              catalogVersion: widget.stats.catalog.version,
              scores: _values,
              reason: _reason!,
              coachNotes: _notes.text.trim(),
            ),
          );
      ref.invalidate(playerStatsProvider(widget.playerId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Player Stats assessment saved.')),
      );
      Navigator.pop(context, result);
    } catch (error) {
      if (!mounted) return;
      final message = friendlyErrorMessage(
        error,
        'Could not save Player Stats.',
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      setState(() {
        _saving = false;
        _saveError = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.stats.latest == null
            ? 'Create Player Stats baseline'
            : 'Update player attributes',
      ),
    ),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.all(16),
      child: Row(
        children: [
          if (_step > 0) ...[
            Expanded(
              child: OutlinedButton(
                key: const Key('stats-back'),
                onPressed: _saving ? null : () => setState(() => _step -= 1),
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              key: Key(_step == 2 ? 'stats-save' : 'stats-continue'),
              onPressed: _saving || (_step == 2 && !_hasChanges)
                  ? null
                  : _step == 2
                  ? _save
                  : _continue,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _step == 2 ? Icons.save_outlined : Icons.arrow_forward,
                    ),
              label: Text(
                _saving
                    ? 'Saving…'
                    : _step == 2
                    ? 'Save assessment'
                    : 'Continue',
              ),
            ),
          ),
        ],
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${widget.playerName} · ${widget.stats.catalog.position} · ${widget.stats.catalog.roleGroup}',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Player Stats use a position-aware 0–99 scale and remain separate from the formal 1–5 Development Assessment.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        _AssessmentStepProgress(current: _step),
        const SizedBox(height: 20),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: switch (_step) {
            0 => Form(
              key: _attributesFormKey,
              child: Column(
                key: const ValueKey('attributes-step'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.stats.latest == null
                        ? 'Set the six baseline attributes'
                        : 'Adjust only what changed',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.stats.latest == null
                        ? 'Every score is required before the baseline can be saved.'
                        : 'The latest values are prefilled. The saved record remains a complete immutable snapshot.',
                  ),
                  const SizedBox(height: 16),
                  for (final attribute in widget.stats.catalog.attributes) ...[
                    _AttributeScoreField(
                      attribute: attribute,
                      controller: _scores[_scoreKey(attribute)]!,
                      previous:
                          widget.stats.latest?.scores[_scoreKey(attribute)],
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
            1 => Form(
              key: _contextFormKey,
              child: Column(
                key: const ValueKey('context-step'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add assessment context',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Explain why the assessment was made and leave useful coaching notes for the player.',
                  ),
                  const SizedBox(height: 16),
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
                    onChanged: (value) => setState(() => _reason = value),
                    validator: (value) =>
                        value == null ? 'Assessment reason is required.' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('stats-coach-notes'),
                    controller: _notes,
                    minLines: 4,
                    maxLines: 8,
                    maxLength: 4000,
                    decoration: const InputDecoration(
                      labelText: 'Coach notes *',
                      hintText:
                          'Describe evidence, progress, and the next coaching focus.',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                    validator: (text) => (text ?? '').trim().isEmpty
                        ? 'Coach notes are required.'
                        : null,
                  ),
                ],
              ),
            ),
            _ => Column(
              key: const ValueKey('review-step'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Review before saving',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text('${_reasonLabel(_reason!)} · Overall $_overall'),
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        for (final attribute in widget.stats.catalog.attributes)
                          _PreviewRow(
                            label: attribute,
                            previous: widget
                                .stats
                                .latest
                                ?.scores[_scoreKey(attribute)],
                            current: _values[_scoreKey(attribute)]!,
                          ),
                        const Divider(),
                        _PreviewRow(
                          label: 'Overall',
                          previous: widget.stats.latest?.overall,
                          current: _overall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (!_hasChanges)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('No attribute changes'),
                      subtitle: Text(
                        'Change at least one score before saving a new snapshot.',
                      ),
                    ),
                  ),
                if (_saveError != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: const Text('Assessment was not saved'),
                      subtitle: Text(_saveError!),
                    ),
                  ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.notes_outlined),
                    title: const Text('Coach notes'),
                    subtitle: Text(_notes.text.trim()),
                  ),
                ),
              ],
            ),
          },
        ),
        const SizedBox(height: 24),
      ],
    ),
  );
}

class _AssessmentStepProgress extends StatelessWidget {
  const _AssessmentStepProgress({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    const labels = ['Attributes', 'Context', 'Review'];
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var index = 0; index < labels.length; index++) ...[
          Expanded(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: index <= current
                      ? colors.primary
                      : colors.surfaceContainerHighest,
                  foregroundColor: index <= current
                      ? colors.onPrimary
                      : colors.onSurfaceVariant,
                  child: index < current
                      ? const Icon(Icons.check, size: 18)
                      : Text('${index + 1}'),
                ),
                const SizedBox(height: 4),
                Text(
                  labels[index],
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: index == current
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (index < labels.length - 1)
            Expanded(
              child: Divider(
                color: index < current ? colors.primary : colors.outlineVariant,
              ),
            ),
        ],
      ],
    );
  }
}

class _AttributeScoreField extends StatelessWidget {
  const _AttributeScoreField({
    required this.attribute,
    required this.controller,
    required this.previous,
    required this.onChanged,
  });

  final String attribute;
  final TextEditingController controller;
  final int? previous;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = int.tryParse(controller.text.trim());
    final delta = previous == null || current == null
        ? null
        : current - previous!;
    return TextFormField(
      key: Key('stats-score-${_scoreKey(attribute)}'),
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: '$attribute *',
        hintText: '0–99',
        helperText: previous == null
            ? 'New baseline value'
            : delta == null || delta == 0
            ? 'Current: $previous'
            : 'Current: $previous · ${delta > 0 ? '+' : ''}$delta',
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
        if (value < 0 || value > 99) return 'Enter a value from 0 to 99.';
        return null;
      },
    );
  }
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

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.assessment,
    required this.previous,
    required this.attributes,
  });

  final PlayerStatsAssessment assessment;
  final PlayerStatsAssessment? previous;
  final List<String> attributes;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final overallDelta = previous == null
        ? null
        : assessment.overall - previous!.overall;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Text('${assessment.overall}')),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${assessment.position} · ${assessment.roleGroup}\n'
                    '${_reasonLabel(assessment.reason)} · ${assessment.assessedBy ?? 'Coach'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(formatFullDate(assessment.createdAt)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                for (final attribute in attributes)
                  _DeltaText(
                    label: attribute,
                    current: assessment.scores[_scoreKey(attribute)] ?? 0,
                    previous: previous?.scores[_scoreKey(attribute)],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              previous == null
                  ? 'Overall ${assessment.overall} · Baseline'
                  : 'Overall ${previous!.overall} → ${assessment.overall} · ${overallDelta == 0 ? 'No change' : '${overallDelta! > 0 ? '+' : ''}$overallDelta'}',
              style: TextStyle(
                color: previous == null || overallDelta == 0
                    ? colors.onSurfaceVariant
                    : overallDelta! > 0
                    ? Colors.green
                    : Colors.red,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (assessment.coachNotes.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(assessment.coachNotes),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeltaText extends StatelessWidget {
  const _DeltaText({required this.label, required this.current, this.previous});
  final String label;
  final int current;
  final int? previous;

  @override
  Widget build(BuildContext context) {
    final delta = previous == null ? null : current - previous!;
    final color = delta == null || delta == 0
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : delta > 0
        ? Colors.green
        : Colors.red;
    return Text(
      '$label ${previous == null ? current : '$previous → $current'}'
      '${delta == null
          ? ' · Baseline'
          : delta == 0
          ? ' · 0'
          : ' · ${delta > 0 ? '+' : ''}$delta'}',
      style: TextStyle(color: color),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.assessments});
  final List<PlayerStatsAssessment> assessments;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(8),
    ),
    child: CustomPaint(
      painter: _TrendPainter(
        assessments.map((value) => value.overall).toList(),
      ),
      child: const SizedBox.expand(),
    ),
  );
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.values);
  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final paint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = size.width * index / (values.length - 1);
      final y = size.height - (values[index] / 99) * size.height;
      index == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.values != values;
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
