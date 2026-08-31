import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/domain/entities/development_assessment.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_growth.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/providers/edit_performance_controller.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/growth_providers.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';

/// Coach Portal — holistic five-domain player development assessment.
class EditPerformanceDataScreen extends ConsumerStatefulWidget {
  const EditPerformanceDataScreen({
    super.key,
    required this.player,
    required this.profile,
  });

  final Player player;
  final UserProfile profile;

  @override
  ConsumerState<EditPerformanceDataScreen> createState() =>
      _EditPerformanceDataScreenState();
}

class _EditPerformanceDataScreenState
    extends ConsumerState<EditPerformanceDataScreen> {
  final _strengthsController = TextEditingController();
  final _targetsController = TextEditingController();
  final _notesController = TextEditingController();
  DevelopmentScores? _scores;
  String? _initializedAssessmentId;
  AssessmentReason _reason = AssessmentReason.generalReview;
  bool _showValidation = false;

  @override
  void dispose() {
    _strengthsController.dispose();
    _targetsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _initialize(DevelopmentAssessmentFormData data) {
    final latestId =
        data.latestAssessment?.id ?? 'empty-v${data.framework.version}';
    if (_initializedAssessmentId == latestId) return;
    final latest = data.latestAssessment;
    _scores = latest?.ratings ?? DevelopmentScores.empty(data.framework);
    _strengthsController.text = latest?.strengths ?? '';
    _targetsController.text = latest?.developmentTargets ?? '';
    _notesController.text = latest?.coachNotes ?? widget.player.coachNotes;
    _initializedAssessmentId = latestId;
  }

  bool _domainComplete(DevelopmentDomain domain) =>
      (_scores?.observedCount(domain.key) ?? 0) >= domain.minimumObserved;

  bool _formComplete(AssessmentFramework framework) =>
      framework.domains.every(_domainComplete) &&
      _strengthsController.text.trim().isNotEmpty &&
      _targetsController.text.trim().isNotEmpty;

  bool _isLargeChange(DevelopmentAssessmentFormData data) {
    final latest = data.latestAssessment;
    final scores = _scores;
    if (latest == null || scores == null) return false;
    for (final domain in data.framework.domains) {
      for (final indicator in domain.indicators) {
        final current = scores.score(domain.key, indicator.key);
        final previous = latest.ratings.score(domain.key, indicator.key);
        if (current != null &&
            previous != null &&
            (current - previous).abs() >= 2) {
          return true;
        }
      }
      final currentAverage = scores.average(domain.key);
      final previousAverage = latest.ratings.average(domain.key);
      if (currentAverage != null &&
          previousAverage != null &&
          (currentAverage - previousAverage).abs() >= 1) {
        return true;
      }
    }
    return false;
  }

  Future<void> _save(DevelopmentAssessmentFormData data) async {
    FocusScope.of(context).unfocus();
    setState(() => _showValidation = true);
    if (!_formComplete(data.framework)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complete the required observations, one strength, and one development target.',
          ),
        ),
      );
      return;
    }
    if (_isLargeChange(data)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm large assessment change'),
          content: const Text(
            'At least one indicator moved by two levels, or a domain moved by one full point. Confirm that the new evidence supports this change.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Review ratings'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm and save'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final draft = DevelopmentAssessmentDraft(
      frameworkVersion: data.framework.version,
      ratings: _scores!,
      strengths: _strengthsController.text.trim(),
      developmentTargets: _targetsController.text.trim(),
      coachNotes: _notesController.text.trim(),
      assessmentReason: _reason.wire,
    );
    final saved = await ref
        .read(editPerformanceControllerProvider.notifier)
        .submit(widget.player.id, draft);
    if (!mounted) return;
    if (saved != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Assessment saved for ${widget.player.name}.')),
      );
      Navigator.of(context).pop(saved);
      return;
    }
    final error = ref.read(editPerformanceControllerProvider).error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          friendlyErrorMessage(
            error,
            'Could not save the assessment. Please try again.',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(developmentAssessmentFormProvider(widget.player.id));
    final isSaving = ref.watch(editPerformanceControllerProvider).isLoading;
    return Scaffold(
      appBar: AppBar(title: const Text('Player Development Assessment')),
      body: form.when(
        loading: () => const DashboardLoadingState(),
        error: (error, _) => DashboardErrorState(
          message: friendlyErrorMessage(
            error,
            'Check your connection and try again.',
          ),
          onRetry: () => ref.invalidate(
            developmentAssessmentFormProvider(widget.player.id),
          ),
        ),
        data: (data) {
          _initialize(data);
          return _AssessmentForm(
            player: widget.player,
            data: data,
            scores: _scores!,
            reason: _reason,
            strengthsController: _strengthsController,
            targetsController: _targetsController,
            notesController: _notesController,
            showValidation: _showValidation,
            isSaving: isSaving,
            domainComplete: _domainComplete,
            onReasonChanged: (value) => setState(() => _reason = value),
            onScoreChanged: (domain, indicator, value) => setState(() {
              _scores = _scores!.withScore(domain, indicator, value);
            }),
            onTextChanged: () => setState(() {}),
            onSave: () => _save(data),
          );
        },
      ),
    );
  }
}

class _AssessmentForm extends StatelessWidget {
  const _AssessmentForm({
    required this.player,
    required this.data,
    required this.scores,
    required this.reason,
    required this.strengthsController,
    required this.targetsController,
    required this.notesController,
    required this.showValidation,
    required this.isSaving,
    required this.domainComplete,
    required this.onReasonChanged,
    required this.onScoreChanged,
    required this.onTextChanged,
    required this.onSave,
  });

  final Player player;
  final DevelopmentAssessmentFormData data;
  final DevelopmentScores scores;
  final AssessmentReason reason;
  final TextEditingController strengthsController;
  final TextEditingController targetsController;
  final TextEditingController notesController;
  final bool showValidation;
  final bool isSaving;
  final bool Function(DevelopmentDomain) domainComplete;
  final ValueChanged<AssessmentReason> onReasonChanged;
  final void Function(String domain, String indicator, int? value)
  onScoreChanged;
  final VoidCallback onTextChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final framework = data.framework;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PlayerContextCard(player: player, data: data),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  framework.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(framework.methodology),
                const SizedBox(height: 6),
                Text(
                  framework.disclaimer,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        if (data.latestAssessment == null)
          const Card(
            child: ListTile(
              leading: Icon(Icons.flag_outlined),
              title: Text('First development assessment'),
              subtitle: Text(
                'There is no previous five-domain assessment. Legacy ratings are not converted.',
              ),
            ),
          ),
        const SizedBox(height: 8),
        for (final domain in framework.domains)
          _DomainCard(
            domain: domain,
            scale: framework.scale,
            scores: scores,
            previous: data.latestAssessment?.ratings,
            showValidation: showValidation,
            onChanged: (indicator, value) =>
                onScoreChanged(domain.key, indicator, value),
          ),
        const SizedBox(height: 16),
        DropdownButtonFormField<AssessmentReason>(
          key: const Key('assessmentReasonField'),
          initialValue: reason,
          decoration: const InputDecoration(
            labelText: 'Assessment reason',
            prefixIcon: Icon(Icons.fact_check_outlined),
          ),
          items: AssessmentReason.values
              .where((value) => value != AssessmentReason.baseline)
              .map(
                (value) =>
                    DropdownMenuItem(value: value, child: Text(value.label)),
              )
              .toList(growable: false),
          onChanged: isSaving
              ? null
              : (value) {
                  if (value != null) onReasonChanged(value);
                },
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('strengthsField'),
          controller: strengthsController,
          minLines: 2,
          maxLines: 4,
          maxLength: 1000,
          onChanged: (_) => onTextChanged(),
          decoration: InputDecoration(
            labelText: 'Observed strength *',
            hintText: 'Describe one clear strength supported by evidence.',
            errorText: showValidation && strengthsController.text.trim().isEmpty
                ? 'Add one observed strength.'
                : null,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('developmentTargetsField'),
          controller: targetsController,
          minLines: 2,
          maxLines: 4,
          maxLength: 1000,
          onChanged: (_) => onTextChanged(),
          decoration: InputDecoration(
            labelText: 'Next development target *',
            hintText: 'Set one observable next action for the player.',
            errorText: showValidation && targetsController.text.trim().isEmpty
                ? 'Add one development target.'
                : null,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('coachNotesField'),
          controller: notesController,
          minLines: 2,
          maxLines: 4,
          maxLength: 2000,
          decoration: const InputDecoration(
            labelText: 'Additional coach notes (optional)',
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('saveDevelopmentAssessmentButton'),
          onPressed: isSaving ? null : onSave,
          icon: isSaving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(isSaving ? 'Saving…' : 'Save assessment'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _PlayerContextCard extends StatelessWidget {
  const _PlayerContextCard({required this.player, required this.data});

  final Player player;
  final DevelopmentAssessmentFormData data;

  @override
  Widget build(BuildContext context) {
    final latest = data.latestAssessment;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage: player.photoUrl == null
              ? null
              : NetworkImage(player.photoUrl!),
          child: player.photoUrl == null
              ? Text(player.name.isEmpty ? '?' : player.name[0])
              : null,
        ),
        title: Text(player.name),
        subtitle: Text(
          '${data.framework.ageTier} · ${data.framework.position.isEmpty ? 'Unassigned position' : data.framework.position}'
          '${latest == null ? '' : ' · Previous ${MaterialLocalizations.of(context).formatMediumDate(latest.createdAt)}'}',
        ),
        trailing: Chip(label: Text(data.framework.positionGroup ?? 'CORE')),
      ),
    );
  }
}

class _DomainCard extends StatelessWidget {
  const _DomainCard({
    required this.domain,
    required this.scale,
    required this.scores,
    required this.previous,
    required this.showValidation,
    required this.onChanged,
  });

  final DevelopmentDomain domain;
  final List<DevelopmentScaleOption> scale;
  final DevelopmentScores scores;
  final DevelopmentScores? previous;
  final bool showValidation;
  final void Function(String indicator, int? value) onChanged;

  @override
  Widget build(BuildContext context) {
    final observed = scores.observedCount(domain.key);
    final complete = observed >= domain.minimumObserved;
    final average = scores.average(domain.key);
    return Card(
      key: Key('domain-${domain.key}'),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(
          domain.label,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '$observed/${domain.indicators.length} observed · minimum ${domain.minimumObserved}',
          style: TextStyle(
            color: showValidation && !complete
                ? Theme.of(context).colorScheme.error
                : null,
          ),
        ),
        trailing: CircleAvatar(child: Text(average?.toStringAsFixed(1) ?? '—')),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(domain.description),
          const SizedBox(height: 4),
          Text(domain.guidance, style: Theme.of(context).textTheme.bodySmall),
          const Divider(height: 24),
          for (final indicator in domain.indicators) ...[
            _IndicatorRating(
              domain: domain,
              indicator: indicator,
              scale: scale,
              value: scores.score(domain.key, indicator.key),
              previous: previous?.score(domain.key, indicator.key),
              onChanged: (value) => onChanged(indicator.key, value),
            ),
            if (indicator != domain.indicators.last) const Divider(height: 24),
          ],
        ],
      ),
    );
  }
}

class _IndicatorRating extends StatelessWidget {
  const _IndicatorRating({
    required this.domain,
    required this.indicator,
    required this.scale,
    required this.value,
    required this.previous,
    required this.onChanged,
  });

  final DevelopmentDomain domain;
  final DevelopmentIndicator indicator;
  final List<DevelopmentScaleOption> scale;
  final int? value;
  final int? previous;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final delta = value != null && previous != null ? value! - previous! : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                indicator.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (indicator.scope == 'POSITION')
              const Chip(label: Text('Position')),
          ],
        ),
        Text(indicator.description),
        if (previous != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Previous $previous${delta == null ? '' : ' · ${delta >= 0 ? '+' : ''}$delta'}',
              style: TextStyle(
                color: delta == null || delta == 0
                    ? Colors.blueGrey
                    : delta > 0
                    ? Colors.green.shade700
                    : Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in scale)
              ChoiceChip(
                key: Key(
                  'score-${domain.key}-${indicator.key}-${option.value ?? 'na'}',
                ),
                label: Text(
                  option.value == null
                      ? 'Not observed'
                      : '${option.value} ${option.label}',
                ),
                selected: value == option.value,
                tooltip: option.description,
                onSelected: (_) => onChanged(option.value),
              ),
          ],
        ),
      ],
    );
  }
}
