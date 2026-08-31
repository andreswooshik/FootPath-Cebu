import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/match_providers.dart';
import 'package:footpath_cebu/presentation/providers/tournament_schedule_providers.dart';

class EditFootballMatchScreen extends ConsumerStatefulWidget {
  const EditFootballMatchScreen({super.key, this.existing, this.fixture});

  final FootballMatch? existing;
  final TournamentFixture? fixture;

  @override
  ConsumerState<EditFootballMatchScreen> createState() =>
      _EditFootballMatchScreenState();
}

class _EditFootballMatchScreenState
    extends ConsumerState<EditFootballMatchScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _opponent;
  late final TextEditingController _competition;
  late final TextEditingController _ourScore;
  late final TextEditingController _opponentScore;
  late DateTime _playedOn;
  late MatchVenue _venue;
  late MatchCategory _category;

  bool get _editing => widget.existing != null;
  bool get _scheduled =>
      widget.fixture != null || widget.existing?.fixtureId != null;

  @override
  void initState() {
    super.initState();
    final match = widget.existing;
    _opponent = TextEditingController(
      text: match?.opponent ?? widget.fixture?.opponent ?? '',
    );
    _competition = TextEditingController(
      text: match?.competition ?? widget.fixture?.tournament ?? '',
    );
    _ourScore = TextEditingController(text: '${match?.ourScore ?? 0}');
    _opponentScore = TextEditingController(
      text: '${match?.opponentScore ?? 0}',
    );
    _playedOn =
        match?.playedOn ??
        widget.fixture?.kickoffAt.toLocal() ??
        DateTime.now();
    _venue = match?.venue ?? widget.fixture?.venue ?? MatchVenue.home;
    _category = _scheduled
        ? MatchCategory.tournament
        : match?.category ?? MatchCategory.other;
  }

  @override
  void dispose() {
    _opponent.dispose();
    _competition.dispose();
    _ourScore.dispose();
    _opponentScore.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _playedOn,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (selected != null) setState(() => _playedOn = selected);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final draft = FootballMatchDraft(
      opponent: _opponent.text,
      competition: _competition.text,
      playedOn: _playedOn,
      venue: _venue,
      ourScore: int.parse(_ourScore.text),
      opponentScore: int.parse(_opponentScore.text),
      fixtureId: widget.fixture?.id,
      category: _category,
    );
    final controller = ref.read(matchManagementControllerProvider.notifier);
    final saved = _editing
        ? await controller.saveMatchChanges(widget.existing!.id, draft)
        : await controller.create(draft);
    if (!mounted) return;
    if (saved != null) {
      if (widget.fixture != null) {
        ref.invalidate(tournamentSchedulesProvider);
      }
      Navigator.of(context).pop(saved);
      return;
    }
    final error = ref.read(matchManagementControllerProvider).error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(friendlyErrorMessage(error, 'Could not save the match.')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(matchManagementControllerProvider).isLoading;
    final date = MaterialLocalizations.of(context).formatMediumDate(_playedOn);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editing
              ? 'Edit Match'
              : _scheduled
              ? 'Record Scheduled Result'
              : 'Record Ad-hoc Match',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _opponent,
              readOnly: _scheduled,
              textCapitalization: TextCapitalization.words,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Opponent',
                prefixIcon: Icon(Icons.shield_outlined),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter the opponent.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _competition,
              readOnly: _scheduled,
              textCapitalization: TextCapitalization.words,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Competition (optional)',
                prefixIcon: Icon(Icons.emoji_events_outlined),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Date played'),
              subtitle: Text(date),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: saving || _scheduled ? null : _pickDate,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<MatchCategory>(
              initialValue: _category,
              decoration: const InputDecoration(
                labelText: 'Match category',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: MatchCategory.values
                  .map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(category.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: saving || _scheduled
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _category = value);
                      }
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<MatchVenue>(
              initialValue: _venue,
              decoration: const InputDecoration(
                labelText: 'Venue',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              items: MatchVenue.values
                  .map(
                    (venue) => DropdownMenuItem(
                      value: venue,
                      child: Text(venue.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: saving || _scheduled
                  ? null
                  : (value) {
                      if (value != null) setState(() => _venue = value);
                    },
            ),
            const SizedBox(height: 20),
            Text('Final Score', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _ScoreField(controller: _ourScore, label: 'Our score'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ScoreField(
                    controller: _opponentScore,
                    label: 'Opponent',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: saving ? null : _save,
              icon: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(saving ? 'Saving…' : 'Save Match'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreField extends StatelessWidget {
  const _ScoreField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
    validator: (value) {
      final number = int.tryParse(value ?? '');
      if (number == null || number < 0 || number > 99) {
        return 'Use 0–99.';
      }
      return null;
    },
  );
}
