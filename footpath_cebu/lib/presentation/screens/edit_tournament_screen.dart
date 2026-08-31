import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/tournament_schedule_providers.dart';
import 'package:footpath_cebu/presentation/widgets/adaptive_form_modal.dart';
import 'package:footpath_cebu/presentation/widgets/app_status_chip.dart';
import 'package:footpath_cebu/presentation/widgets/responsive_content.dart';

class EditTournamentScreen extends ConsumerStatefulWidget {
  const EditTournamentScreen({super.key, this.existing});

  final TournamentSchedule? existing;

  @override
  ConsumerState<EditTournamentScreen> createState() =>
      _EditTournamentScreenState();
}

class _EditTournamentScreenState extends ConsumerState<EditTournamentScreen> {
  late final TextEditingController _titleController = TextEditingController(
    text: widget.existing?.title ?? '',
  );
  late final TextEditingController _venueController = TextEditingController(
    text: widget.existing?.venue ?? '',
  );
  late DateTime? _startsOn = widget.existing?.startsOn;
  late TournamentSchedule? _current = widget.existing;
  String? _formError;

  @override
  void dispose() {
    _titleController.dispose();
    _venueController.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startsOn ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _startsOn = picked);
  }

  Future<void> _saveDetails() async {
    final title = _titleController.text.trim();
    final venue = _venueController.text.trim();
    if (title.isEmpty || venue.isEmpty || _startsOn == null) {
      setState(
        () => _formError = 'Enter a tournament name, venue, and start date.',
      );
      return;
    }
    final controller = ref.read(
      tournamentManagementControllerProvider.notifier,
    );
    final saved = _current == null
        ? await controller.create(
            title: title,
            venue: venue,
            startsOn: _startsOn!,
          )
        : await controller.saveTournament(
            _current!.copyWith(title: title, venue: venue, startsOn: _startsOn),
          );
    if (!mounted) return;
    if (saved == null) {
      _showError('Could not save the tournament.');
      return;
    }
    setState(() {
      _current = saved;
      _formError = null;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Tournament draft saved.')));
  }

  Future<void> _editBracket([TournamentAgeBracket? existing]) async {
    final result =
        await showAdaptiveFormModal<({int maxAge, DateTime? scheduledAt})>(
          context: context,
          builder: (context) => _BracketEditor(existing: existing),
        );
    if (result == null || _current == null) return;
    final controller = ref.read(
      tournamentManagementControllerProvider.notifier,
    );
    final saved = existing == null
        ? await controller.addBracket(
            _current!.id,
            maxAge: result.maxAge,
            scheduledAt: result.scheduledAt,
          )
        : await controller.updateBracket(
            existing.id,
            maxAge: result.maxAge,
            scheduledAt: result.scheduledAt,
          );
    if (!mounted) return;
    if (saved == null) {
      _showError('Could not save the age bracket.');
      return;
    }
    setState(() => _current = saved);
  }

  Future<void> _removeBracket(TournamentAgeBracket bracket) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${bracket.label}?'),
        content: const Text(
          'This removes the age bracket from the tournament draft.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep bracket'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await ref
        .read(tournamentManagementControllerProvider.notifier)
        .deleteBracket(bracket.id);
    if (!mounted) return;
    if (!ok) {
      _showError('Could not remove the age bracket.');
      return;
    }
    setState(() {
      _current = _current!.copyWith(
        ageBrackets: _current!.ageBrackets
            .where((row) => row.id != bracket.id)
            .toList(),
      );
    });
  }

  Future<void> _publish() async {
    if (_current == null) return;
    if (_current!.ageBrackets.isEmpty) {
      setState(() => _formError = 'Add at least one age bracket first.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publish tournament?'),
        content: const Text(
          'Players and guardians will be able to see the tournament and its age brackets.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final saved = await ref
        .read(tournamentManagementControllerProvider.notifier)
        .publish(_current!.id);
    if (!mounted) return;
    if (saved == null) {
      _showError('Could not publish the tournament.');
      return;
    }
    setState(() => _current = saved);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tournament published to the club.')),
    );
  }

  void _showError(String fallback) {
    final error = ref.read(tournamentManagementControllerProvider).error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyErrorMessage(error, fallback))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = ref.watch(
      tournamentManagementControllerProvider.select((state) => state.isLoading),
    );
    final tournament = _current;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tournament == null ? 'New tournament' : 'Manage tournament',
        ),
      ),
      body: ResponsiveContent(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  tournament?.isPublished == true
                      ? 'Published tournament'
                      : 'Tournament draft',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                AppStatusChip(
                  label: tournament?.isPublished == true
                      ? 'Published'
                      : 'Draft',
                  tone: tournament?.isPublished == true
                      ? AppStatusTone.success
                      : AppStatusTone.neutral,
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _titleController,
              enabled: !isSaving,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Tournament name',
                hintText: 'e.g. Sinulog Cup',
                prefixIcon: Icon(Icons.emoji_events_outlined),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _venueController,
              enabled: !isSaving,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Tournament venue',
                hintText: 'e.g. Cebu City Sports Center',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: isSaving ? null : _pickStartDate,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _startsOn == null
                      ? 'Choose tournament start date'
                      : formatFullDate(_startsOn!),
                ),
              ),
            ),
            if (_formError != null) ...[
              const SizedBox(height: 12),
              Text(
                _formError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: isSaving ? null : _saveDetails,
              icon: isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(tournament == null ? 'Save draft' : 'Save details'),
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Age brackets',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (tournament != null)
                  OutlinedButton.icon(
                    onPressed: isSaving ? null : () => _editBracket(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add bracket'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (tournament == null)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Save the tournament draft before adding U-age brackets.',
                  ),
                ),
              )
            else if (tournament.ageBrackets.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No brackets yet. Add U8, U10, U12, or another division.',
                  ),
                ),
              )
            else
              for (final bracket in tournament.ageBrackets)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text(bracket.label)),
                    title: Text('${bracket.label} division'),
                    subtitle: Text(
                      bracket.scheduledAt == null
                          ? 'Schedule date and time: TBD'
                          : _formatDateTime(context, bracket.scheduledAt!),
                    ),
                    trailing: PopupMenuButton<_BracketAction>(
                      enabled: !isSaving,
                      tooltip: '${bracket.label} actions',
                      onSelected: (action) {
                        switch (action) {
                          case _BracketAction.edit:
                            _editBracket(bracket);
                            break;
                          case _BracketAction.remove:
                            _removeBracket(bracket);
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: _BracketAction.edit,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Edit bracket'),
                          ),
                        ),
                        if (!tournament.isPublished)
                          const PopupMenuItem(
                            value: _BracketAction.remove,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.delete_outline),
                              title: Text('Remove bracket'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 24),
            const Card(
              child: ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('Official schedule document'),
                subtitle: Text(
                  'Upload or replace the private PDF, JPG, or PNG in the web portal.',
                ),
              ),
            ),
            if (tournament != null && !tournament.isPublished) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: isSaving ? null : _publish,
                icon: isSaving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.publish_outlined),
                label: const Text('Publish tournament'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _BracketAction { edit, remove }

class _BracketEditor extends StatefulWidget {
  const _BracketEditor({this.existing});

  final TournamentAgeBracket? existing;

  @override
  State<_BracketEditor> createState() => _BracketEditorState();
}

class _BracketEditorState extends State<_BracketEditor> {
  late int? _maxAge = widget.existing?.maxAge;
  late DateTime? _scheduledAt = widget.existing?.scheduledAt?.toLocal();
  String? _error;

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _scheduledAt == null
          ? TimeOfDay.now()
          : TimeOfDay.fromDateTime(_scheduledAt!),
    );
    if (time == null) return;
    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _submit() {
    final age = _maxAge;
    if (age == null) {
      setState(() => _error = 'Choose an age bracket.');
      return;
    }
    Navigator.pop(context, (maxAge: age, scheduledAt: _scheduledAt));
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.existing == null ? 'Add age bracket' : 'Edit age bracket',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<int>(
          key: const Key('tournament-age-bracket-dropdown'),
          initialValue: _maxAge,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Age bracket',
            helperText: 'Choose U3 through U21.',
            errorText: _error,
          ),
          items: [
            for (var age = 3; age <= 21; age++)
              DropdownMenuItem(value: age, child: Text('U$age')),
          ],
          onChanged: (value) => setState(() {
            _maxAge = value;
            _error = null;
          }),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _pickSchedule,
          icon: const Icon(Icons.event_outlined),
          label: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _scheduledAt == null
                  ? 'Add optional schedule date and time'
                  : _formatDateTime(context, _scheduledAt!),
            ),
          ),
        ),
        if (_scheduledAt != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _scheduledAt = null),
              child: const Text('Clear schedule time'),
            ),
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(onPressed: _submit, child: const Text('Save bracket')),
          ],
        ),
      ],
    ),
  );
}

String _formatDateTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final time = MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay.fromDateTime(local));
  return '${formatFullDate(local)} at $time';
}
