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
  final _formKey = GlobalKey<FormState>();
  late final _description = TextEditingController(
    text: widget.existing?.description,
  );
  late final _bodyPart = TextEditingController(text: widget.existing?.bodyPart);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late DateTime _occurredOn = widget.existing?.occurredOn ?? DateTime.now();
  late InjuryStatus _status = widget.existing?.status ?? InjuryStatus.active;
  late DateTime? _resolvedOn = widget.existing?.resolvedOn;

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

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_coordinatorConfirmed &&
        _status == InjuryStatus.recovered &&
        _resolvedOn == null) {
      _message('Choose the recovery date.');
      return;
    }
    final existing = widget.existing;
    final bodyPart = _blankAsNull(_bodyPart.text);
    final notes = _blankAsNull(_notes.text);
    final record = existing == null
        ? InjuryRecord(
            playerId: widget.playerId,
            description: _description.text.trim(),
            status: InjuryStatus.active,
            occurredOn: _occurredOn,
            bodyPart: bodyPart,
            notes: notes,
          )
        : existing.copyWith(
            description: _description.text.trim(),
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
      _message(
        friendlyErrorMessage(
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              editing ? 'Edit Injury Report' : 'Report Injury',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              editing
                  ? 'Update the factual details below.'
                  : 'The club Coordinator will confirm this report before it is posted.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _description,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Description *',
                hintText: 'e.g. Sprained ankle',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'A description is required.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bodyPart,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Body part'),
            ),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Date of injury'),
              subtitle: Text(formatFullDate(_occurredOn)),
              onTap: saving ? null : _pickDate,
            ),
            if (_coordinatorConfirmed) ...[
              const SizedBox(height: 8),
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
                        if (_status != InjuryStatus.recovered) {
                          _resolvedOn = null;
                        }
                      }),
              ),
              if (_status == InjuryStatus.recovered)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_available_outlined),
                  title: const Text('Recovery date'),
                  subtitle: Text(
                    _resolvedOn == null
                        ? 'Choose a date'
                        : formatFullDate(_resolvedOn!),
                  ),
                  onTap: saving ? null : () => _pickDate(resolved: true),
                ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              minLines: 3,
              maxLines: 5,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Private care notes (optional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: saving ? null : _save,
              icon: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(editing ? 'Save Changes' : 'Submit Report'),
            ),
            if (widget.existing?.canEditPending == true)
              TextButton(
                onPressed: saving ? null : _withdraw,
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Withdraw Pending Report'),
              ),
          ],
        ),
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
