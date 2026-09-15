import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/injury_record.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/injury_providers.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/injury_status_chip.dart';

class InjuryHistoryScreen extends ConsumerWidget {
  const InjuryHistoryScreen({
    super.key,
    required this.playerId,
    required this.playerName,
    this.readOnly = false,
  });

  final String playerId;
  final String playerName;
  final bool readOnly;

  Future<void> _openReport(BuildContext context, {InjuryRecord? existing}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: InjuryReportFormSheet(playerId: playerId, existing: existing),
        ),
      );

  Future<void> _openStatusUpdate(BuildContext context, InjuryRecord record) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: InjuryStatusUpdateSheet(record: record),
        ),
      );

  void _showDetails(BuildContext context, InjuryRecord record) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(record.description),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Report: ${record.reviewStatus.label}'),
            Text('Type: ${record.injuryType.label}'),
            Text('Severity: ${record.severity.label}'),
            Text('Injury status: ${record.status.label}'),
            if (record.reporterName.isNotEmpty)
              Text('Reported by: ${record.reporterName}'),
            if (record.notes?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(record.notes!),
            ],
            if (record.rejectionReason?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text('Reason: ${record.rejectionReason}'),
            ],
            if (record.pendingStatusUpdate != null) ...[
              const SizedBox(height: 8),
              Text(
                '${record.pendingStatusUpdate!.proposedStatus.label} update awaiting Coordinator review.',
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _openRecord(BuildContext context, InjuryRecord record) {
    if (readOnly) return;
    if (record.canEditPending) {
      _openReport(context, existing: record);
    } else if (record.canRequestStatusUpdate) {
      _openStatusUpdate(context, record);
    } else {
      _showDetails(context, record);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final injuries = ref.watch(injuriesProvider(playerId));
    return Scaffold(
      appBar: AppBar(title: Text('Injuries - $playerName')),
      body: injuries.when(
        loading: () => const DashboardLoadingState(),
        error: (error, _) => DashboardErrorState(
          message: friendlyErrorMessage(
            error,
            'Something went wrong loading injuries.',
          ),
          onRetry: () => ref.invalidate(injuriesProvider(playerId)),
        ),
        data: (records) => RefreshIndicator(
          onRefresh: () => ref.refresh(injuriesProvider(playerId).future),
          child: records.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(32),
                  children: [
                    const SizedBox(height: 72),
                    Text(
                      readOnly
                          ? 'No injuries on record.'
                          : 'No injury reports. Tap "Report Injury" to submit one.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: records.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final record = records[index];
                    return Card(
                      child: ListTile(
                        title: Text(record.description),
                        subtitle: Text(_subtitle(record)),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            InjuryStatusChip(status: record.status),
                            Text(
                              record.reviewStatus.label,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                        onTap: readOnly
                            ? null
                            : () => _openRecord(context, record),
                      ),
                    ).animateListItem(
                      key: ValueKey(record.id ?? '${record.occurredOn}-$index'),
                      index: index,
                    );
                  },
                ),
        ),
      ),
      floatingActionButton: readOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openReport(context),
              icon: const Icon(Icons.add),
              label: const Text('Report Injury'),
            ),
    ).animateScreenEntrance();
  }

  String _subtitle(InjuryRecord record) {
    final parts = [
      record.severity.label,
      if (record.bodyPart != null) record.bodyPart!,
      formatFullDate(record.occurredOn),
      if (record.pendingStatusUpdate != null) 'Recovery update pending',
    ];
    return parts.join(' - ');
  }
}

class InjuryReportFormSheet extends ConsumerStatefulWidget {
  const InjuryReportFormSheet({
    super.key,
    required this.playerId,
    this.existing,
  });

  final String playerId;
  final InjuryRecord? existing;

  @override
  ConsumerState<InjuryReportFormSheet> createState() =>
      _InjuryReportFormSheetState();
}

class _InjuryReportFormSheetState extends ConsumerState<InjuryReportFormSheet> {
  late final _description = TextEditingController(
    text: widget.existing?.description,
  );
  late final _bodyPart = TextEditingController(text: widget.existing?.bodyPart);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late InjuryType _injuryType = widget.existing?.injuryType ?? InjuryType.other;
  late InjurySeverity _severity =
      widget.existing?.severity ?? InjurySeverity.moderate;
  late DateTime _occurredOn = widget.existing?.occurredOn ?? DateTime.now();
  late InjuryStatus _status = widget.existing?.status ?? InjuryStatus.active;
  late DateTime? _resolvedOn = widget.existing?.resolvedOn;
  int _step = 0;
  String? _stepError;
  String? _submitError;

  bool get _coordinatorConfirmed =>
      widget.existing?.reviewStatus == InjuryReportStatus.confirmed &&
      widget.existing?.canEditConfirmed == true;

  @override
  void dispose() {
    _description.dispose();
    _bodyPart.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _blankAsNull(String value) {
    final cleaned = value.trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  Future<void> _pickDate({bool resolved = false}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: resolved ? (_resolvedOn ?? DateTime.now()) : _occurredOn,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (selected == null) return;
    setState(() {
      if (resolved) {
        _resolvedOn = selected;
      } else {
        _occurredOn = selected;
      }
    });
  }

  void _selectType(InjuryType value) {
    setState(() {
      _injuryType = value;
      _stepError = null;
    });
  }

  void _selectSeverity(InjurySeverity value) {
    setState(() {
      _severity = value;
      _stepError = null;
    });
  }

  void _continue() {
    FocusScope.of(context).unfocus();
    if (_step == 2 && _description.text.trim().isEmpty) {
      setState(() => _stepError = 'Describe what happened before continuing.');
      return;
    }
    if (_coordinatorConfirmed &&
        _step == 2 &&
        _status == InjuryStatus.recovered &&
        _resolvedOn == null) {
      setState(() => _stepError = 'Choose the recovery date.');
      return;
    }
    setState(() {
      _stepError = null;
      _submitError = null;
      _step += 1;
    });
  }

  void _back() {
    FocusScope.of(context).unfocus();
    setState(() {
      _stepError = null;
      _submitError = null;
      _step -= 1;
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_description.text.trim().isEmpty) {
      setState(() {
        _step = 2;
        _stepError = 'Describe what happened before submitting.';
      });
      return;
    }
    if (_coordinatorConfirmed &&
        _status == InjuryStatus.recovered &&
        _resolvedOn == null) {
      setState(() {
        _step = 2;
        _stepError = 'Choose the recovery date.';
      });
      return;
    }
    setState(() => _submitError = null);
    final existing = widget.existing;
    final bodyPart = _blankAsNull(_bodyPart.text);
    final notes = _blankAsNull(_notes.text);
    final record = existing == null
        ? InjuryRecord(
            playerId: widget.playerId,
            description: _description.text.trim(),
            injuryType: _injuryType,
            severity: _severity,
            status: InjuryStatus.active,
            occurredOn: _occurredOn,
            bodyPart: bodyPart,
            notes: notes,
          )
        : existing.copyWith(
            description: _description.text.trim(),
            injuryType: _injuryType,
            severity: _severity,
            status: _coordinatorConfirmed ? _status : InjuryStatus.active,
            occurredOn: _occurredOn,
            bodyPart: bodyPart,
            clearBodyPart: bodyPart == null,
            resolvedOn: _status == InjuryStatus.recovered ? _resolvedOn : null,
            clearResolvedOn: _status != InjuryStatus.recovered,
            notes: notes,
            clearNotes: notes == null,
          );
    final saved = await ref
        .read(injuryFormControllerProvider.notifier)
        .submit(record);
    if (!mounted) return;
    if (saved == null) {
      setState(
        () => _submitError = friendlyErrorMessage(
          ref.read(injuryFormControllerProvider).error,
          'Could not save the injury report.',
        ),
      );
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          existing == null
              ? 'Injury report submitted for confirmation.'
              : 'Injury report updated.',
        ),
      ),
    );
  }

  Future<void> _withdraw() async {
    final record = widget.existing;
    if (record == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Withdraw this report?'),
        content: const Text('The Pending injury report will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep report'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await ref
        .read(injuryFormControllerProvider.notifier)
        .remove(record);
    if (!mounted) return;
    if (!removed) {
      _message('Could not withdraw the injury report.');
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Injury report withdrawn.')));
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(injuryFormControllerProvider).isLoading;
    final editing = widget.existing != null;
    final height = MediaQuery.sizeOf(context).height * 0.84;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        editing ? 'Edit injury report' : 'Report an injury',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        editing
                            ? 'Review each step before saving.'
                            : 'The Coordinator will review this private report.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: saving ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          _InjuryStepProgress(currentStep: _step),
          const Divider(height: 1),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: SingleChildScrollView(
                key: ValueKey(_step),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: _stepContent(saving),
              ),
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  if (_step > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving ? null : _back,
                        child: const Text('Back'),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: saving
                          ? null
                          : _step == 3
                          ? _save
                          : _continue,
                      icon: saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _step == 3
                                  ? Icons.send_outlined
                                  : Icons.arrow_forward,
                            ),
                      label: Text(
                        _step == 3
                            ? editing
                                  ? 'Save changes'
                                  : 'Submit report'
                            : 'Continue',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepContent(bool saving) {
    final theme = Theme.of(context);
    final error = _stepError ?? (_step == 3 ? _submitError : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_stepTitles[_step], style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          _stepDescriptions[_step],
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        if (_step == 0) _typeStep(saving),
        if (_step == 1) _severityStep(saving),
        if (_step == 2) _notesStep(saving),
        if (_step == 3) _reviewStep(),
        if (error != null) ...[
          const SizedBox(height: 16),
          _InjuryInlineMessage(message: error, isError: true),
        ],
        if (_step == 3 && widget.existing?.canEditPending == true) ...[
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: saving ? null : _withdraw,
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Withdraw pending report'),
          ),
        ],
      ],
    );
  }

  Widget _typeStep(bool saving) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final type in InjuryType.values)
            ChoiceChip(
              label: Text(type.label),
              selected: _injuryType == type,
              onSelected: saving ? null : (_) => _selectType(type),
            ),
        ],
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _bodyPart,
        enabled: !saving,
        maxLength: 80,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Body part (optional)',
          hintText: 'e.g. Left ankle',
          prefixIcon: Icon(Icons.accessibility_new_outlined),
        ),
      ),
      const SizedBox(height: 4),
      Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(Icons.calendar_today_outlined),
          title: const Text('Date of injury'),
          subtitle: Text(formatFullDate(_occurredOn)),
          trailing: const Icon(Icons.chevron_right),
          onTap: saving ? null : _pickDate,
        ),
      ),
    ],
  );

  Widget _severityStep(bool saving) => Column(
    children: [
      for (final severity in InjurySeverity.values) ...[
        _SeverityOption(
          severity: severity,
          selected: _severity == severity,
          onTap: saving ? null : () => _selectSeverity(severity),
        ),
        if (severity != InjurySeverity.values.last) const SizedBox(height: 12),
      ],
      const SizedBox(height: 16),
      const _InjuryInlineMessage(
        message:
            'For severe injuries or head impacts, stop activity and seek appropriate medical care.',
      ),
    ],
  );

  Widget _notesStep(bool saving) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _description,
        enabled: !saving,
        minLines: 2,
        maxLines: 4,
        maxLength: 200,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) {
          if (_stepError != null) setState(() => _stepError = null);
        },
        decoration: const InputDecoration(
          labelText: 'What happened? *',
          hintText: 'Describe the injury and how it happened',
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _notes,
        enabled: !saving,
        minLines: 3,
        maxLines: 5,
        maxLength: 1000,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Private care notes (optional)',
          hintText: 'Treatment, restrictions, or follow-up details',
          alignLabelWithHint: true,
        ),
      ),
      if (_coordinatorConfirmed) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<InjuryStatus>(
          initialValue: _status,
          decoration: const InputDecoration(labelText: 'Injury status'),
          items: [
            for (final value in InjuryStatus.values)
              DropdownMenuItem(value: value, child: Text(value.label)),
          ],
          onChanged: saving
              ? null
              : (value) => setState(() {
                  _status = value ?? _status;
                  _stepError = null;
                  if (_status != InjuryStatus.recovered) _resolvedOn = null;
                }),
        ),
        if (_status == InjuryStatus.recovered)
          Card(
            margin: const EdgeInsets.only(top: 12),
            child: ListTile(
              leading: const Icon(Icons.event_available_outlined),
              title: const Text('Recovery date'),
              subtitle: Text(
                _resolvedOn == null
                    ? 'Choose a date'
                    : formatFullDate(_resolvedOn!),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: saving ? null : () => _pickDate(resolved: true),
            ),
          ),
      ],
    ],
  );

  Widget _reviewStep() => Column(
    children: [
      _ReviewRow(label: 'Type', value: _injuryType.label),
      _ReviewRow(label: 'Severity', value: _severity.label),
      _ReviewRow(
        label: 'Body part',
        value: _blankAsNull(_bodyPart.text) ?? 'Not specified',
      ),
      _ReviewRow(label: 'Occurred', value: formatFullDate(_occurredOn)),
      _ReviewRow(label: 'Details', value: _description.text.trim()),
      if (_blankAsNull(_notes.text) case final notes?)
        _ReviewRow(label: 'Private notes', value: notes),
      const SizedBox(height: 14),
      const _InjuryInlineMessage(
        message:
            'Submitting shares this report only with the player’s authorized club care team.',
      ),
    ],
  );
}

const _stepTitles = ['Injury type', 'Severity', 'Notes', 'Review and submit'];
const _stepDescriptions = [
  'Choose the closest category and tell us where it happened.',
  'Select the current impact on the player.',
  'Add the details the care team needs to review.',
  'Confirm the information before sending the report.',
];

class _InjuryStepProgress extends StatelessWidget {
  const _InjuryStepProgress({required this.currentStep});

  final int currentStep;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const labels = ['Type', 'Severity', 'Notes', 'Submit'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            Expanded(
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: index <= currentStep
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                    ),
                    child: index < currentStep
                        ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: index <= currentStep
                                  ? scheme.onPrimary
                                  : scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    labels[index],
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: index <= currentStep
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                      fontWeight: index == currentStep
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
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

class _SeverityOption extends StatelessWidget {
  const _SeverityOption({
    required this.severity,
    required this.selected,
    required this.onTap,
  });

  final InjurySeverity severity;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: selected ? scheme.primaryContainer : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        ),
        title: Text(
          severity.label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(severity.guidance),
        onTap: onTap,
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class _InjuryInlineMessage extends StatelessWidget {
  const _InjuryInlineMessage({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = isError
        ? scheme.errorContainer
        : scheme.secondaryContainer;
    final foreground = isError
        ? scheme.onErrorContainer
        : scheme.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            color: foreground,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: foreground)),
          ),
        ],
      ),
    );
  }
}

class InjuryStatusUpdateSheet extends ConsumerStatefulWidget {
  const InjuryStatusUpdateSheet({super.key, required this.record});

  final InjuryRecord record;

  @override
  ConsumerState<InjuryStatusUpdateSheet> createState() =>
      _InjuryStatusUpdateSheetState();
}

class _InjuryStatusUpdateSheetState
    extends ConsumerState<InjuryStatusUpdateSheet> {
  late InjuryStatus _status = widget.record.status == InjuryStatus.recovering
      ? InjuryStatus.recovered
      : InjuryStatus.recovering;
  DateTime? _resolvedOn;
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickResolvedDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _resolvedOn ?? DateTime.now(),
      firstDate: widget.record.occurredOn,
      lastDate: DateTime.now(),
    );
    if (selected != null) setState(() => _resolvedOn = selected);
  }

  Future<void> _submit() async {
    if (_status == InjuryStatus.recovered && _resolvedOn == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose the recovery date.')),
      );
      return;
    }
    final ok = await ref
        .read(injuryFormControllerProvider.notifier)
        .requestStatus(
          widget.record,
          InjuryStatusUpdateDraft(
            proposedStatus: _status,
            proposedResolvedOn: _resolvedOn,
            notes: InjuryRecord.blankAsNull(_notes.text.trim()),
          ),
        );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not submit the recovery update.')),
      );
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recovery update sent to the Coordinator.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(injuryFormControllerProvider).isLoading;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Request Recovery Update',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          const Text('The Coordinator must approve this change.'),
          const SizedBox(height: 16),
          DropdownButtonFormField<InjuryStatus>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'New status'),
            items: const [
              DropdownMenuItem(
                value: InjuryStatus.recovering,
                child: Text('Recovering'),
              ),
              DropdownMenuItem(
                value: InjuryStatus.recovered,
                child: Text('Recovered'),
              ),
            ],
            onChanged: saving
                ? null
                : (value) => setState(() {
                    _status = value ?? _status;
                    if (_status != InjuryStatus.recovered) _resolvedOn = null;
                  }),
          ),
          if (_status == InjuryStatus.recovered)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Recovery date'),
              subtitle: Text(
                _resolvedOn == null
                    ? 'Choose a date'
                    : formatFullDate(_resolvedOn!),
              ),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: saving ? null : _pickResolvedDate,
            ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notes,
            minLines: 3,
            maxLines: 5,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Update notes (optional)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: saving ? null : _submit,
            icon: const Icon(Icons.send_outlined),
            label: const Text('Submit Update'),
          ),
        ],
      ),
    );
  }
}
