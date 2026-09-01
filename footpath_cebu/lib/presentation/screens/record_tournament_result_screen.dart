import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/domain/entities/tournament_roster.dart';
import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/tournament_schedule_providers.dart';
import 'package:footpath_cebu/presentation/widgets/adaptive_form_modal.dart';
import 'package:footpath_cebu/presentation/widgets/responsive_content.dart';

class RecordTournamentResultScreen extends ConsumerStatefulWidget {
  const RecordTournamentResultScreen({
    super.key,
    required this.tournament,
    required this.fixture,
  });

  final TournamentSchedule tournament;
  final TournamentFixture fixture;

  @override
  ConsumerState<RecordTournamentResultScreen> createState() =>
      _RecordTournamentResultScreenState();
}

class _RecordTournamentResultScreenState
    extends ConsumerState<RecordTournamentResultScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ourScore = TextEditingController(text: '0');
  final _opponentScore = TextEditingController(text: '0');
  final Map<String, TournamentParticipantStatisticsDraft> _participants = {};
  String? _error;

  TournamentAgeBracket? get _bracket {
    for (final bracket in widget.tournament.ageBrackets) {
      if (bracket.id == widget.fixture.ageBracketId) return bracket;
    }
    return null;
  }

  List<TournamentSquadEntry> get _squadEntries =>
      _bracket?.squad?.entries ?? const [];

  @override
  void dispose() {
    _ourScore.dispose();
    _opponentScore.dispose();
    super.dispose();
  }

  void _toggle(TournamentSquadEntry entry, bool selected) {
    setState(() {
      if (selected) {
        _participants[entry.playerId] = TournamentParticipantStatisticsDraft(
          playerId: entry.playerId,
          position: entry.tournamentPosition,
        );
      } else {
        _participants.remove(entry.playerId);
      }
      _error = null;
    });
  }

  Future<void> _editStatistics(TournamentSquadEntry entry) async {
    final current = _participants[entry.playerId];
    if (current == null) return;
    final updated =
        await showAdaptiveFormModal<TournamentParticipantStatisticsDraft>(
          context: context,
          builder: (context) => _ParticipantStatisticsEditor(
            playerId: entry.playerId,
            playerName: entry.playerName,
            initial: current,
          ),
        );
    if (updated != null && mounted) {
      setState(() => _participants[entry.playerId] = updated);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_participants.isEmpty) {
      setState(() => _error = 'Select at least one participating player.');
      return;
    }
    final result = TournamentResultDraft(
      ourScore: int.parse(_ourScore.text),
      opponentScore: int.parse(_opponentScore.text),
      participants: _participants.values.toList(growable: false),
    );
    final saved = await ref
        .read(tournamentManagementControllerProvider.notifier)
        .recordResult(widget.fixture.id, result);
    if (!mounted) return;
    if (saved == null) {
      final error = ref.read(tournamentManagementControllerProvider).error;
      setState(
        () => _error = friendlyErrorMessage(
          error,
          'Could not record the tournament result.',
        ),
      );
      return;
    }
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(tournamentManagementControllerProvider).isLoading;
    return Scaffold(
      appBar: AppBar(title: const Text('Record Tournament Result')),
      body: ResponsiveContent(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              Text(
                '${widget.tournament.title} · ${widget.fixture.ageBracketLabel ?? 'Tournament'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'vs ${widget.fixture.opponent} · ${widget.fixture.stage}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              Text(
                'Final Score',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _NumberField(
                      controller: _ourScore,
                      label: 'FootPath Cebu',
                      maximum: 99,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumberField(
                      controller: _opponentScore,
                      label: 'Opponent',
                      maximum: 99,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Participating Players',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'Select players from the Coach-published squad, then enter objective match statistics. Coach ratings and feedback remain separate.',
              ),
              const SizedBox(height: 12),
              if (_squadEntries.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'The Coach must publish this age bracket’s squad before a result can be recorded.',
                    ),
                  ),
                )
              else
                for (final entry in _squadEntries)
                  Card(
                    child: Column(
                      children: [
                        CheckboxListTile(
                          value: _participants.containsKey(entry.playerId),
                          onChanged: saving
                              ? null
                              : (value) => _toggle(entry, value ?? false),
                          title: Text(entry.playerName),
                          subtitle: Text(
                            entry.tournamentPosition.isEmpty
                                ? 'Position not assigned'
                                : entry.tournamentPosition,
                          ),
                        ),
                        if (_participants[entry.playerId] case final stats?)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 12, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${stats.minutesPlayed} min · ${stats.goals} goals · ${stats.assists} assists · ${stats.tackles} tackles',
                                  ),
                                ),
                                TextButton(
                                  onPressed: saving
                                      ? null
                                      : () => _editStatistics(entry),
                                  child: const Text('Edit Statistics'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: saving || _squadEntries.isEmpty ? null : _save,
                icon: saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sports_score_outlined),
                label: const Text('Record Result and Player Statistics'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParticipantStatisticsEditor extends StatefulWidget {
  const _ParticipantStatisticsEditor({
    required this.playerId,
    required this.playerName,
    required this.initial,
  });

  final String playerId;
  final String playerName;
  final TournamentParticipantStatisticsDraft initial;

  @override
  State<_ParticipantStatisticsEditor> createState() =>
      _ParticipantStatisticsEditorState();
}

class _ParticipantStatisticsEditorState
    extends State<_ParticipantStatisticsEditor> {
  final _formKey = GlobalKey<FormState>();
  late String _position = widget.initial.position;
  late bool _starter = widget.initial.starter;
  late bool _cleanSheet = widget.initial.cleanSheet;
  late final Map<String, TextEditingController> _fields = {
    'minutes': TextEditingController(text: '${widget.initial.minutesPlayed}'),
    'goals': TextEditingController(text: '${widget.initial.goals}'),
    'assists': TextEditingController(text: '${widget.initial.assists}'),
    'shots': TextEditingController(text: '${widget.initial.shots}'),
    'shotsOnTarget': TextEditingController(
      text: '${widget.initial.shotsOnTarget}',
    ),
    'passesAttempted': TextEditingController(
      text: '${widget.initial.passesAttempted}',
    ),
    'passesCompleted': TextEditingController(
      text: '${widget.initial.passesCompleted}',
    ),
    'tackles': TextEditingController(text: '${widget.initial.tackles}'),
    'interceptions': TextEditingController(
      text: '${widget.initial.interceptions}',
    ),
    'yellowCards': TextEditingController(text: '${widget.initial.yellowCards}'),
    'redCards': TextEditingController(text: '${widget.initial.redCards}'),
    'saves': TextEditingController(text: '${widget.initial.saves}'),
    'goalsConceded': TextEditingController(
      text: '${widget.initial.goalsConceded}',
    ),
  };

  int _value(String key) => int.parse(_fields[key]!.text);

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_value('shotsOnTarget') > _value('shots')) {
      _message('Shots on target cannot exceed total shots.');
      return;
    }
    if (_value('goals') > _value('shotsOnTarget')) {
      _message('Goals cannot exceed shots on target.');
      return;
    }
    if (_value('passesCompleted') > _value('passesAttempted')) {
      _message('Completed passes cannot exceed attempted passes.');
      return;
    }
    if (_position != 'GK' &&
        (_value('saves') > 0 || _value('goalsConceded') > 0 || _cleanSheet)) {
      _message('Goalkeeper statistics require the GK position.');
      return;
    }
    Navigator.pop(
      context,
      TournamentParticipantStatisticsDraft(
        playerId: widget.playerId,
        position: _position,
        starter: _starter,
        minutesPlayed: _value('minutes'),
        goals: _value('goals'),
        assists: _value('assists'),
        shots: _value('shots'),
        shotsOnTarget: _value('shotsOnTarget'),
        passesAttempted: _value('passesAttempted'),
        passesCompleted: _value('passesCompleted'),
        tackles: _value('tackles'),
        interceptions: _value('interceptions'),
        yellowCards: _value('yellowCards'),
        redCards: _value('redCards'),
        saves: _value('saves'),
        goalsConceded: _value('goalsConceded'),
        cleanSheet: _cleanSheet,
      ),
    );
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
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
            widget.playerName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _position.isEmpty ? null : _position,
            decoration: const InputDecoration(labelText: 'Match position'),
            items: [
              for (final value in [
                'GK',
                'CB',
                'LB',
                'RB',
                'CDM',
                'CM',
                'CAM',
                'LW',
                'RW',
                'ST',
              ])
                DropdownMenuItem(value: value, child: Text(value)),
            ],
            validator: (value) => value == null ? 'Choose a position.' : null,
            onChanged: (value) => setState(() => _position = value ?? ''),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Started the match'),
            value: _starter,
            onChanged: (value) => setState(() => _starter = value),
          ),
          _StatsGrid(fields: _fields),
          if (_position == 'GK')
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Clean sheet'),
              value: _cleanSheet,
              onChanged: (value) => setState(() => _cleanSheet = value),
            ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Save Statistics')),
        ],
      ),
    ),
  );
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.fields});

  final Map<String, TextEditingController> fields;

  static const labels = {
    'minutes': 'Minutes',
    'goals': 'Goals',
    'assists': 'Assists',
    'shots': 'Shots',
    'shotsOnTarget': 'Shots on target',
    'passesAttempted': 'Passes attempted',
    'passesCompleted': 'Passes completed',
    'tackles': 'Tackles',
    'interceptions': 'Interceptions',
    'yellowCards': 'Yellow cards',
    'redCards': 'Red cards',
    'saves': 'Saves (GK)',
    'goalsConceded': 'Goals conceded (GK)',
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth > 540
          ? (constraints.maxWidth - 12) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final entry in fields.entries)
            SizedBox(
              width: width,
              child: _NumberField(
                controller: entry.value,
                label: labels[entry.key]!,
                maximum: entry.key == 'minutes'
                    ? 180
                    : entry.key == 'yellowCards'
                    ? 2
                    : entry.key == 'redCards'
                    ? 1
                    : null,
              ),
            ),
        ],
      );
    },
  );
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    this.maximum,
  });

  final TextEditingController controller;
  final String label;
  final int? maximum;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
    validator: (value) {
      final number = int.tryParse(value ?? '');
      if (number == null ||
          number < 0 ||
          (maximum != null && number > maximum!)) {
        return maximum == null ? 'Use 0 or more.' : 'Use 0–$maximum.';
      }
      return null;
    },
  );
}
