import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/injury_record.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/injury_providers.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/injury_status_chip.dart';

/// One player's injury history — a task/detail screen (no bottom nav).
///
/// The player reaches it from their dashboard and can add/edit/delete; the
/// coach reaches it from a player profile with [readOnly] set. The read-only
/// flag is UX only — the server denies coach writes regardless.
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

  Future<void> _openForm(BuildContext context, {InjuryRecord? existing}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _InjuryFormSheet(playerId: playerId, existing: existing),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final injuriesAsync = ref.watch(injuriesProvider(playerId));
    return Scaffold(
      appBar: AppBar(title: Text('Injuries · $playerName')),
      body: injuriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => DashboardErrorState(
          message: friendlyErrorMessage(
            e,
            'Something went wrong loading injuries.',
          ),
          onRetry: () => ref.invalidate(injuriesProvider(playerId)),
        ),
        data: (records) {
          if (records.isEmpty) {
            return Center(
              child: Text(
                readOnly
                    ? 'No injuries on record.'
                    : 'No injuries logged. Tap "Log Injury" to add one.',
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(injuriesProvider(playerId).future),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: records.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final record = records[index];
                return Card(
                  child: ListTile(
                    title: Text(record.description),
                    subtitle: Text(_subtitle(record)),
                    trailing: InjuryStatusChip(status: record.status),
                    onTap: readOnly
                        ? null
                        : () => _openForm(context, existing: record),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: readOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openForm(context),
              icon: const Icon(Icons.add),
              label: const Text('Log Injury'),
            ),
    );
  }

  String _subtitle(InjuryRecord record) {
    final parts = [
      if (record.bodyPart != null) record.bodyPart!,
      formatFullDate(record.occurredOn),
      if (record.resolvedOn != null)
        'resolved ${formatFullDate(record.resolvedOn!)}',
    ];
    return parts.join(' · ');
  }
}

/// Add/edit form. Field values live here (View concerns); submit/delete state
/// lives in [InjuryFormController].
class _InjuryFormSheet extends ConsumerStatefulWidget {
  const _InjuryFormSheet({required this.playerId, this.existing});

  final String playerId;
  final InjuryRecord? existing;

  @override
  ConsumerState<_InjuryFormSheet> createState() => _InjuryFormSheetState();
}

class _InjuryFormSheetState extends ConsumerState<_InjuryFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _descriptionController =
      TextEditingController(text: widget.existing?.description);
  late final _bodyPartController =
      TextEditingController(text: widget.existing?.bodyPart);
  late final _notesController =
      TextEditingController(text: widget.existing?.notes);
  late InjuryStatus _status = widget.existing?.status ?? InjuryStatus.active;
  late DateTime _occurredOn = widget.existing?.occurredOn ?? DateTime.now();
  late DateTime? _resolvedOn = widget.existing?.resolvedOn;

  @override
  void dispose() {
    _descriptionController.dispose();
    _bodyPartController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String? _nullIfBlank(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _pickDate({required bool resolved}) async {
    final initial = resolved ? (_resolvedOn ?? DateTime.now()) : _occurredOn;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (resolved) {
        _resolvedOn = picked;
      } else {
        _occurredOn = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final record = InjuryRecord(
      id: widget.existing?.id,
      playerId: widget.playerId,
      description: _descriptionController.text.trim(),
      status: _status,
      occurredOn: _occurredOn,
      bodyPart: _nullIfBlank(_bodyPartController.text),
      resolvedOn: _resolvedOn,
      notes: _nullIfBlank(_notesController.text),
    );
    final saved =
        await ref.read(injuryFormControllerProvider.notifier).submit(record);
    if (!mounted) return;
    if (saved == null) {
      final error = ref.read(injuryFormControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(error, 'Could not save the injury.'),
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Injury saved.')),
    );
  }

  Future<void> _delete() async {
    final record = widget.existing;
    if (record == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this injury?'),
        content: Text('"${record.description}" will be removed permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok =
        await ref.read(injuryFormControllerProvider.notifier).remove(record);
    if (!mounted) return;
    if (!ok) {
      final error = ref.read(injuryFormControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(error, 'Could not delete the injury.'),
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Injury deleted.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = ref.watch(injuryFormControllerProvider).isLoading;
    final editing = widget.existing != null;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                editing ? 'Edit Injury' : 'Log Injury',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description *',
                  hintText: 'e.g. Sprained ankle',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'A description is required.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bodyPartController,
                decoration: const InputDecoration(
                  labelText: 'Body part',
                  hintText: 'e.g. Left ankle',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<InjuryStatus>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final status in InjuryStatus.values)
                    DropdownMenuItem(
                      value: status,
                      child: Text(status.label),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _status = value ?? _status),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date of injury'),
                subtitle: Text(formatFullDate(_occurredOn)),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () => _pickDate(resolved: false),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date resolved'),
                subtitle: Text(
                  _resolvedOn == null
                      ? 'Not yet resolved'
                      : formatFullDate(_resolvedOn!),
                ),
                trailing: _resolvedOn == null
                    ? const Icon(Icons.calendar_today_outlined)
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear resolved date',
                        onPressed: () => setState(() => _resolvedOn = null),
                      ),
                onTap: () => _pickDate(resolved: true),
              ),
              TextFormField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'How it happened, treatment, restrictions…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: isSaving ? null : _save,
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(editing ? 'Save Changes' : 'Log Injury'),
              ),
              if (editing)
                TextButton(
                  onPressed: isSaving ? null : _delete,
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: const Text('Delete Injury'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
