import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/tournament_roster.dart';
import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';
import 'package:footpath_cebu/domain/repositories/tournament_schedule_repository.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/tournament_schedule_providers.dart';
import 'package:footpath_cebu/presentation/widgets/adaptive_form_modal.dart';
import 'package:footpath_cebu/presentation/widgets/app_status_chip.dart';
import 'package:footpath_cebu/presentation/widgets/responsive_content.dart';

enum _ManageSection { overview, brackets, fixtures, squads, document }

extension on _ManageSection {
  String get label => switch (this) {
    _ManageSection.overview => 'Overview',
    _ManageSection.brackets => 'Age Brackets',
    _ManageSection.fixtures => 'Fixtures',
    _ManageSection.squads => 'Squads',
    _ManageSection.document => 'Document',
  };
}

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
  _ManageSection _section = _ManageSection.overview;
  TournamentDocumentUpload? _selectedDocument;
  String? _selectedDocumentName;
  String? _formError;
  String? _fixtureBracketFilter;
  String? _fixtureStageFilter;
  TournamentFixtureStatus? _fixtureStatusFilter;

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

  Future<void> _pickDocument() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.isEmpty) {
      setState(() => _formError = 'Could not read the selected document.');
      return;
    }
    if (bytes.length > 5 * 1024 * 1024) {
      setState(() => _formError = 'The document must be 5 MB or smaller.');
      return;
    }
    final extension = (file.extension ?? '').toLowerCase();
    final contentType = switch (extension) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      _ => null,
    };
    if (contentType == null) {
      setState(() => _formError = 'Choose a PDF, JPG, or PNG document.');
      return;
    }
    setState(() {
      _selectedDocument = TournamentDocumentUpload(
        bytes: bytes,
        filename: file.name,
        contentType: contentType,
      );
      _selectedDocumentName = file.name;
      _formError = null;
    });
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
    TournamentSchedule? saved;
    if (_current == null) {
      saved = await controller.create(
        title: title,
        venue: venue,
        startsOn: _startsOn!,
        document: _selectedDocument,
      );
    } else {
      saved = await controller.saveTournament(
        _current!.copyWith(title: title, venue: venue, startsOn: _startsOn),
      );
      if (saved != null && _selectedDocument != null) {
        saved = await controller.uploadDocument(saved.id, _selectedDocument!);
      }
    }
    if (!mounted) return;
    if (saved == null) {
      _showError('Could not save the tournament.');
      return;
    }
    setState(() {
      _current = saved;
      _selectedDocument = null;
      _selectedDocumentName = null;
      _formError = null;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Tournament draft saved.')));
  }

  Future<void> _editBracket([TournamentAgeBracket? existing]) async {
    final result =
        await showAdaptiveFormModal<
          ({int maxAge, DateTime? scheduledAt, Set<AgeTier> academyTiers})
        >(
          context: context,
          builder: (context) => _BracketEditor(existing: existing),
        );
    if (result == null || _current == null) return;
    final controller = ref.read(
      tournamentManagementControllerProvider.notifier,
    );
    var saved = existing == null
        ? await controller.addBracket(
            _current!.id,
            maxAge: result.maxAge,
            scheduledAt: result.scheduledAt,
            academyTiers: result.academyTiers,
          )
        : await controller.updateBracket(
            existing.id,
            maxAge: result.maxAge,
            scheduledAt: result.scheduledAt,
            academyTiers: result.academyTiers,
          );
    if (saved == null &&
        existing != null &&
        _needsTrainingCancellationConfirmation()) {
      final confirmed = await _confirm(
        title: 'Cancel conflicting training?',
        message:
            'Changing this bracket tier affects future tournament fixtures. '
            'Confirming keeps overlapping training in history as Cancelled.',
        action: 'Confirm tier change',
      );
      if (confirmed && mounted) {
        saved = await controller.updateBracket(
          existing.id,
          maxAge: result.maxAge,
          scheduledAt: result.scheduledAt,
          academyTiers: result.academyTiers,
          confirmTrainingCancellations: true,
        );
      }
    }
    if (!mounted) return;
    if (saved == null) {
      _showError('Could not save the age bracket.');
      return;
    }
    setState(() => _current = saved);
  }

  Future<void> _removeBracket(TournamentAgeBracket bracket) async {
    final confirmed = await _confirm(
      title: 'Remove ${bracket.label}?',
      message: 'This removes the age bracket from the tournament draft.',
      action: 'Remove bracket',
    );
    if (!confirmed || !mounted) return;
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

  Future<void> _editFixture([TournamentFixture? existing]) async {
    final tournament = _current;
    if (tournament == null) return;
    final result = await showAdaptiveFormModal<TournamentFixtureDraft>(
      context: context,
      builder: (context) =>
          _FixtureEditor(brackets: tournament.ageBrackets, existing: existing),
    );
    if (result == null) return;
    final controller = ref.read(
      tournamentManagementControllerProvider.notifier,
    );
    var saved = existing == null
        ? await controller.addFixture(tournament.id, result)
        : await controller.updateFixture(existing.id, result);
    if (saved == null && _needsTrainingCancellationConfirmation()) {
      final confirmed = await _confirm(
        title: 'Cancel conflicting training?',
        message:
            'This fixture overlaps future training for the same academy tier. '
            'The tournament takes priority. Confirming keeps the training in '
            'history as Cancelled and notifies affected users.',
        action: 'Confirm fixture',
      );
      if (confirmed && mounted) {
        saved = existing == null
            ? await controller.addFixture(
                tournament.id,
                result,
                confirmTrainingCancellations: true,
              )
            : await controller.updateFixture(
                existing.id,
                result,
                confirmTrainingCancellations: true,
              );
      }
    }
    if (!mounted) return;
    if (saved == null) {
      _showError('Could not save the fixture.');
      return;
    }
    setState(() => _current = saved);
  }

  Future<void> _removeFixture(TournamentFixture fixture) async {
    final confirmed = await _confirm(
      title: 'Delete fixture?',
      message: 'The fixture against ${fixture.opponent} will be removed.',
      action: 'Delete fixture',
    );
    if (!confirmed || !mounted) return;
    final ok = await ref
        .read(tournamentManagementControllerProvider.notifier)
        .deleteFixture(fixture.id);
    if (!mounted) return;
    if (!ok) {
      _showError('Could not delete the fixture.');
      return;
    }
    setState(() {
      _current = _current!.copyWith(
        fixtures: _current!.fixtures
            .where((row) => row.id != fixture.id)
            .toList(),
      );
    });
  }

  Future<void> _replaceDocument() async {
    if (_current == null || _selectedDocument == null) return;
    final saved = await ref
        .read(tournamentManagementControllerProvider.notifier)
        .uploadDocument(_current!.id, _selectedDocument!);
    if (!mounted) return;
    if (saved == null) {
      _showError('Could not upload the document.');
      return;
    }
    setState(() {
      _current = saved;
      _selectedDocument = null;
      _selectedDocumentName = null;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Official document updated.')));
  }

  Future<void> _removeDocument() async {
    final tournament = _current;
    if (tournament == null) return;
    final confirmed = await _confirm(
      title: 'Remove official document?',
      message: 'Manual age brackets and fixtures will remain available.',
      action: 'Remove document',
    );
    if (!confirmed || !mounted) return;
    final ok = await ref
        .read(tournamentManagementControllerProvider.notifier)
        .removeDocument(tournament.id);
    if (!mounted) return;
    if (!ok) {
      _showError('Could not remove the document.');
      return;
    }
    setState(
      () => _current = tournament.copyWith(
        hasDocument: false,
        clearDocumentUrl: true,
      ),
    );
  }

  Future<void> _openDocument() async {
    final url = _current?.documentUrl;
    if (url == null || url.isEmpty) return;
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) _showMessage('Could not open the document.');
  }

  Future<void> _publish() async {
    final tournament = _current;
    if (tournament == null) return;
    final localErrors = <String>[];
    if (_titleController.text.trim().isEmpty) localErrors.add('a name');
    if (_venueController.text.trim().isEmpty) localErrors.add('a venue');
    if (_startsOn == null) localErrors.add('a start date');
    if (tournament.ageBrackets.isEmpty) localErrors.add('an age bracket');
    if (tournament.fixtures.isEmpty) localErrors.add('a valid fixture');
    if (localErrors.isNotEmpty) {
      setState(
        () => _formError = 'Before publishing, add ${localErrors.join(', ')}.',
      );
      return;
    }
    final confirmed = await _confirm(
      title: 'Publish tournament?',
      message:
          'Publishing makes the schedule visible to Coaches, Players, and Guardians.',
      action: 'Publish tournament',
    );
    if (!confirmed || !mounted) return;
    var saved = await ref
        .read(tournamentManagementControllerProvider.notifier)
        .publish(tournament.id);
    if (saved == null && _needsTrainingCancellationConfirmation()) {
      final cancelTraining = await _confirm(
        title: 'Cancel conflicting training?',
        message:
            'Publishing will cancel future training that overlaps a tournament '
            'fixture for the same academy tier. Sessions stay in history and '
            'affected users are notified.',
        action: 'Publish and cancel training',
      );
      if (cancelTraining && mounted) {
        saved = await ref
            .read(tournamentManagementControllerProvider.notifier)
            .publish(tournament.id, confirmTrainingCancellations: true);
      }
    }
    if (!mounted) return;
    if (saved == null) {
      _showError('Could not publish the tournament.');
      return;
    }
    setState(() {
      _current = saved;
      _formError = null;
    });
    _showMessage('Tournament published to the club.');
  }

  Future<void> _deleteTournament() async {
    final tournament = _current;
    if (tournament == null) return;
    final confirmed = await _confirm(
      title: 'Delete tournament?',
      message:
          'The document, brackets, and uncompleted fixtures will be removed. Completed tournament history is protected.',
      action: 'Delete tournament',
    );
    if (!confirmed || !mounted) return;
    final ok = await ref
        .read(tournamentManagementControllerProvider.notifier)
        .deleteTournament(tournament.id);
    if (!mounted) return;
    if (!ok) {
      _showError('Could not delete the tournament.');
      return;
    }
    Navigator.of(context).pop();
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  void _showError(String fallback) {
    final error = ref.read(tournamentManagementControllerProvider).error;
    _showMessage(friendlyErrorMessage(error, fallback));
  }

  bool _needsTrainingCancellationConfirmation() {
    final error = ref.read(tournamentManagementControllerProvider).error;
    return error is TournamentScheduleRepositoryException &&
        error.statusCode == 409;
  }

  void _showMessage(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
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
          tournament == null ? 'Create Tournament' : 'Manage Tournament',
        ),
      ),
      body: ResponsiveContent(
        child: Column(
          children: [
            if (tournament != null)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: SegmentedButton<_ManageSection>(
                  showSelectedIcon: false,
                  segments: [
                    for (final section in _ManageSection.values)
                      ButtonSegment(value: section, label: Text(section.label)),
                  ],
                  selected: {_section},
                  onSelectionChanged: isSaving
                      ? null
                      : (value) => setState(() => _section = value.first),
                ),
              ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                children: [
                  _Header(tournament: tournament),
                  if (_formError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _formError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (tournament == null || _section == _ManageSection.overview)
                    _overview(isSaving)
                  else if (_section == _ManageSection.brackets)
                    _brackets(isSaving, tournament)
                  else if (_section == _ManageSection.fixtures)
                    _fixtures(isSaving, tournament)
                  else if (_section == _ManageSection.squads)
                    _squads(tournament)
                  else
                    _document(isSaving, tournament),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _overview(bool isSaving) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
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
          labelText: 'Main venue',
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
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: isSaving ? null : _pickDocument,
        icon: const Icon(Icons.upload_file_outlined),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _selectedDocumentName ??
                (_current?.hasDocument == true
                    ? 'Choose a replacement document'
                    : 'Add optional PDF, JPG, or PNG'),
          ),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: isSaving ? null : _saveDetails,
        icon: isSaving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save_outlined),
        label: Text(_current == null ? 'Save draft' : 'Save details'),
      ),
      if (_current != null && !_current!.isPublished) ...[
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: isSaving ? null : _publish,
          icon: const Icon(Icons.publish_outlined),
          label: const Text('Publish tournament'),
        ),
      ],
      if (_current != null) ...[
        const SizedBox(height: 32),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: isSaving ? null : _deleteTournament,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete tournament'),
        ),
      ],
    ],
  );

  Widget _brackets(bool isSaving, TournamentSchedule tournament) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Age Brackets',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          OutlinedButton.icon(
            onPressed: isSaving ? null : () => _editBracket(),
            icon: const Icon(Icons.add),
            label: const Text('Add bracket'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (tournament.ageBrackets.isEmpty)
        const _EmptyCard(
          message: 'No brackets yet. Add a U-age division to continue.',
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
                tooltip: '${bracket.label} actions',
                onSelected: (action) => switch (action) {
                  _BracketAction.edit => _editBracket(bracket),
                  _BracketAction.remove => _removeBracket(bracket),
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _BracketAction.edit,
                    child: Text('Edit bracket'),
                  ),
                  if (!tournament.isPublished)
                    const PopupMenuItem(
                      value: _BracketAction.remove,
                      child: Text('Remove bracket'),
                    ),
                ],
              ),
            ),
          ),
    ],
  );

  Widget _fixtures(bool isSaving, TournamentSchedule tournament) {
    final stages =
        tournament.fixtures
            .map((row) => row.stage)
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final rows =
        tournament.fixtures.where((fixture) {
            return (_fixtureBracketFilter == null ||
                    fixture.ageBracketId == _fixtureBracketFilter) &&
                (_fixtureStageFilter == null ||
                    fixture.stage == _fixtureStageFilter) &&
                (_fixtureStatusFilter == null ||
                    fixture.status == _fixtureStatusFilter);
          }).toList()
          ..sort((left, right) => left.kickoffAt.compareTo(right.kickoffAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Manual Fixtures',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            FilledButton.tonalIcon(
              onPressed: isSaving || tournament.ageBrackets.isEmpty
                  ? null
                  : () => _editFixture(),
              icon: const Icon(Icons.add),
              label: const Text('Add Fixture'),
            ),
          ],
        ),
        if (tournament.ageBrackets.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Add an age bracket before creating a fixture.'),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _FilterDropdown<String>(
              label: 'Age bracket',
              value: _fixtureBracketFilter,
              allLabel: 'All brackets',
              options: {
                for (final row in tournament.ageBrackets) row.id: row.label,
              },
              onChanged: (value) =>
                  setState(() => _fixtureBracketFilter = value),
            ),
            _FilterDropdown<String>(
              label: 'Stage',
              value: _fixtureStageFilter,
              allLabel: 'All stages',
              options: {for (final value in stages) value: value},
              onChanged: (value) => setState(() => _fixtureStageFilter = value),
            ),
            _FilterDropdown<TournamentFixtureStatus>(
              label: 'Status',
              value: _fixtureStatusFilter,
              allLabel: 'All statuses',
              options: {
                for (final value in TournamentFixtureStatus.values)
                  value: value.label,
              },
              onChanged: (value) =>
                  setState(() => _fixtureStatusFilter = value),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const _EmptyCard(message: 'No fixtures match the selected filters.')
        else
          for (final fixture in rows)
            _ManageFixtureCard(
              fixture: fixture,
              onEdit: fixture.hasResult ? null : () => _editFixture(fixture),
              onDelete: fixture.hasResult
                  ? null
                  : () => _removeFixture(fixture),
            ),
      ],
    );
  }

  Widget _squads(TournamentSchedule tournament) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Tournament Squads', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      const Text(
        'Coaches manage squads; Coordinators can review their status here.',
      ),
      const SizedBox(height: 12),
      if (tournament.ageBrackets.isEmpty)
        const _EmptyCard(
          message: 'Add age brackets before squads are prepared.',
        )
      else
        for (final bracket in tournament.ageBrackets)
          Card(
            child: ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: Text('${bracket.label} squad'),
              subtitle: Text(
                bracket.squad == null
                    ? 'Not started'
                    : '${bracket.squad!.status.label} · ${bracket.squad!.entries.length} players',
              ),
            ),
          ),
    ],
  );

  Widget _document(bool isSaving, TournamentSchedule tournament) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Official Schedule Document',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 4),
      Text(
        tournament.hasDocument
            ? 'A private official document is attached.'
            : 'No document is required. Manual fixtures are a complete alternative.',
      ),
      const SizedBox(height: 16),
      if (tournament.documentUrl?.isNotEmpty == true)
        OutlinedButton.icon(
          onPressed: _openDocument,
          icon: const Icon(Icons.open_in_new),
          label: const Text('Open Document'),
        ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: isSaving ? null : _pickDocument,
        icon: const Icon(Icons.attach_file),
        label: Text(_selectedDocumentName ?? 'Choose PDF, JPG, or PNG'),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: isSaving || _selectedDocument == null
            ? null
            : _replaceDocument,
        icon: const Icon(Icons.upload_file_outlined),
        label: Text(
          tournament.hasDocument ? 'Replace Document' : 'Upload Document',
        ),
      ),
      if (tournament.hasDocument) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: isSaving ? null : _removeDocument,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Remove Document'),
        ),
      ],
    ],
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.tournament});

  final TournamentSchedule? tournament;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 8,
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        tournament == null ? 'New tournament draft' : tournament!.title,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      AppStatusChip(
        label: tournament?.lifecycleStatus.label ?? 'Draft',
        tone: switch (tournament?.lifecycleStatus) {
          TournamentLifecycleStatus.published => AppStatusTone.info,
          TournamentLifecycleStatus.inProgress => AppStatusTone.warning,
          TournamentLifecycleStatus.completed => AppStatusTone.success,
          _ => AppStatusTone.neutral,
        },
      ),
    ],
  );
}

class _ManageFixtureCard extends StatelessWidget {
  const _ManageFixtureCard({
    required this.fixture,
    required this.onEdit,
    required this.onDelete,
  });

  final TournamentFixture fixture;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'vs ${fixture.opponent}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              AppStatusChip(
                label: fixture.status.label,
                tone: fixture.hasResult
                    ? AppStatusTone.success
                    : AppStatusTone.info,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${fixture.ageBracketLabel ?? 'No bracket'} · ${fixture.stage}\n'
            '${_formatDateTime(context, fixture.kickoffAt)}\n'
            '${fixture.venue.label} · ${fixture.location}',
          ),
          const SizedBox(height: 10),
          if (fixture.hasResult)
            const Text('Completed fixture details are protected.')
          else
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: onEdit,
                  child: const Text('Edit Fixture'),
                ),
                TextButton(
                  onPressed: onDelete,
                  child: const Text('Delete Fixture'),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(16), child: Text(message)),
  );
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.allLabel,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final String allLabel;
  final Map<T, String> options;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: DropdownButtonFormField<T?>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        DropdownMenuItem<T?>(value: null, child: Text(allLabel)),
        for (final entry in options.entries)
          DropdownMenuItem<T?>(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: onChanged,
    ),
  );
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
  late Set<AgeTier> _academyTiers = {...?widget.existing?.academyTiers};
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
    if (_academyTiers.isEmpty) {
      setState(() => _error = 'Select at least one academy tier.');
      return;
    }
    Navigator.pop(context, (
      maxAge: age,
      scheduledAt: _scheduledAt,
      academyTiers: _academyTiers,
    ));
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
            _academyTiers = switch (value) {
              12 => {AgeTier.foundation},
              15 => {AgeTier.development},
              18 => {AgeTier.pathway},
              _ => _academyTiers,
            };
            _error = null;
          }),
        ),
        const SizedBox(height: 16),
        Text('Academy tiers', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tier in AgeTier.values)
              FilterChip(
                label: Text(tier.label),
                selected: _academyTiers.contains(tier),
                onSelected: (selected) => setState(() {
                  selected
                      ? _academyTiers.add(tier)
                      : _academyTiers.remove(tier);
                  _error = null;
                }),
              ),
          ],
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
        const SizedBox(height: 16),
        FilledButton(onPressed: _submit, child: const Text('Save bracket')),
      ],
    ),
  );
}

class _FixtureEditor extends StatefulWidget {
  const _FixtureEditor({required this.brackets, this.existing});

  final List<TournamentAgeBracket> brackets;
  final TournamentFixture? existing;

  @override
  State<_FixtureEditor> createState() => _FixtureEditorState();
}

class _FixtureEditorState extends State<_FixtureEditor> {
  final _formKey = GlobalKey<FormState>();
  late String? _bracketId = widget.existing?.ageBracketId;
  late final TextEditingController _stage = TextEditingController(
    text: widget.existing?.stage ?? '',
  );
  late final TextEditingController _opponent = TextEditingController(
    text: widget.existing?.opponent ?? 'TBD',
  );
  late final TextEditingController _location = TextEditingController(
    text: widget.existing?.location ?? '',
  );
  late DateTime _kickoff =
      widget.existing?.kickoffAt.toLocal() ??
      DateTime.now().add(const Duration(days: 1));
  late DateTime _endsAt =
      widget.existing?.effectiveEndsAt.toLocal() ??
      _kickoff.add(const Duration(hours: 2));
  late MatchVenue _venue = widget.existing?.venue ?? MatchVenue.neutral;
  late TournamentFixtureStatus _status =
      widget.existing?.status ?? TournamentFixtureStatus.scheduled;

  @override
  void dispose() {
    _stage.dispose();
    _opponent.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickKickoff() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _kickoff,
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime(DateTime.now().year + 10),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_kickoff),
    );
    if (time == null) return;
    setState(() {
      _kickoff = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (!_endsAt.isAfter(_kickoff)) {
        _endsAt = _kickoff.add(const Duration(hours: 2));
      }
    });
  }

  Future<void> _pickEnd() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _endsAt,
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime(DateTime.now().year + 10),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_endsAt),
    );
    if (time == null) return;
    setState(() {
      _endsAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate() || _bracketId == null) return;
    if (!_endsAt.isAfter(_kickoff)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expected end must be after kickoff.')),
      );
      return;
    }
    Navigator.pop(
      context,
      TournamentFixtureDraft(
        ageBracketId: _bracketId!,
        stage: _stage.text,
        opponent: _opponent.text,
        kickoffAt: _kickoff,
        endsAt: _endsAt,
        venue: _venue,
        location: _location.text,
        status: _status,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _formKey,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.existing == null ? 'Add Fixture' : 'Edit Fixture',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _bracketId,
            decoration: const InputDecoration(labelText: 'Age bracket'),
            items: [
              for (final bracket in widget.brackets)
                DropdownMenuItem(value: bracket.id, child: Text(bracket.label)),
            ],
            validator: (value) =>
                value == null ? 'Choose an age bracket.' : null,
            onChanged: (value) => setState(() => _bracketId = value),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _stage,
            decoration: const InputDecoration(
              labelText: 'Stage or round',
              hintText: 'Group Stage, Quarterfinal, Semifinal, or Final',
            ),
            validator: _required,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _opponent,
            decoration: const InputDecoration(
              labelText: 'Opponent',
              helperText: 'Use TBD when the opponent is not yet known.',
            ),
            validator: _required,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickKickoff,
            icon: const Icon(Icons.schedule),
            label: Text(_formatDateTime(context, _kickoff)),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickEnd,
            icon: const Icon(Icons.timer_outlined),
            label: Text('Expected end: ${_formatDateTime(context, _endsAt)}'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<MatchVenue>(
            initialValue: _venue,
            decoration: const InputDecoration(labelText: 'Venue type'),
            items: [
              for (final venue in MatchVenue.values)
                DropdownMenuItem(value: venue, child: Text(venue.label)),
            ],
            onChanged: (value) => setState(() => _venue = value!),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _location,
            decoration: const InputDecoration(
              labelText: 'Location, pitch, or stadium',
            ),
            validator: _required,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<TournamentFixtureStatus>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: [
              for (final status in TournamentFixtureStatus.values)
                if (status != TournamentFixtureStatus.completed)
                  DropdownMenuItem(value: status, child: Text(status.label)),
            ],
            onChanged: (value) => setState(() => _status = value!),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Save Fixture')),
        ],
      ),
    ),
  );
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'This field is required.' : null;

String _formatDateTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final time = MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay.fromDateTime(local));
  return '${formatFullDate(local)} at $time';
}
