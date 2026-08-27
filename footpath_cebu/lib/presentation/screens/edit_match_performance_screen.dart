import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/match_performance.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/match_providers.dart';

class EditMatchPerformanceScreen extends ConsumerStatefulWidget {
  const EditMatchPerformanceScreen({
    super.key,
    required this.match,
    required this.player,
    this.existing,
  });

  final FootballMatch match;
  final Player player;
  final MatchPerformance? existing;

  @override
  ConsumerState<EditMatchPerformanceScreen> createState() =>
      _EditMatchPerformanceScreenState();
}

class _EditMatchPerformanceScreenState
    extends ConsumerState<EditMatchPerformanceScreen> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _numbers;
  late final TextEditingController _rating;
  late final TextEditingController _notes;
  late PlayerPosition? _position;
  late bool _starter;
  late bool _cleanSheet;

  MatchPerformance? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final row = _existing;
    _position = PlayerPositionInfo.fromWire(
      row?.position ?? widget.player.position?.wire,
    );
    _starter = row?.starter ?? false;
    _cleanSheet = row?.cleanSheet ?? false;
    _numbers = {
      'minutes': _controller(row?.minutesPlayed ?? 0),
      'goals': _controller(row?.goals ?? 0),
      'assists': _controller(row?.assists ?? 0),
      'shots': _controller(row?.shots ?? 0),
      'shotsOnTarget': _controller(row?.shotsOnTarget ?? 0),
      'passesAttempted': _controller(row?.passesAttempted ?? 0),
      'passesCompleted': _controller(row?.passesCompleted ?? 0),
      'tackles': _controller(row?.tackles ?? 0),
      'interceptions': _controller(row?.interceptions ?? 0),
      'yellowCards': _controller(row?.yellowCards ?? 0),
      'redCards': _controller(row?.redCards ?? 0),
      'saves': _controller(row?.saves ?? 0),
      'goalsConceded': _controller(row?.goalsConceded ?? 0),
    };
    _rating = TextEditingController(
      text: row?.coachRating.toStringAsFixed(1) ?? '5.0',
    );
    _notes = TextEditingController(text: row?.notes ?? '');
  }

  TextEditingController _controller(int value) =>
      TextEditingController(text: '$value');

  @override
  void dispose() {
    for (final controller in _numbers.values) {
      controller.dispose();
    }
    _rating.dispose();
    _notes.dispose();
    super.dispose();
  }

  int _value(String key) => int.parse(_numbers[key]!.text);

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_position == null) {
      _showMessage('Select the player’s match position.');
      return;
    }
    if (_value('shotsOnTarget') > _value('shots')) {
      _showMessage('Shots on target cannot exceed total shots.');
      return;
    }
    if (_value('goals') > _value('shotsOnTarget')) {
      _showMessage('Goals cannot exceed shots on target.');
      return;
    }
    if (_value('passesCompleted') > _value('passesAttempted')) {
      _showMessage('Completed passes cannot exceed attempted passes.');
      return;
    }
    if (_cleanSheet && _value('goalsConceded') > 0) {
      _showMessage('A clean sheet cannot include goals conceded.');
      return;
    }
    final draft = MatchPerformanceDraft(
      position: _position!.wire,
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
      coachRating: double.parse(_rating.text),
      notes: _notes.text,
    );
    final saved = await ref
        .read(matchManagementControllerProvider.notifier)
        .savePerformance(widget.match.id, widget.player.id, draft);
    if (!mounted) return;
    if (saved != null) {
      Navigator.of(context).pop(saved);
      return;
    }
    _showMessage(
      friendlyErrorMessage(
        ref.read(matchManagementControllerProvider).error,
        'Could not save match statistics.',
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove statistics?'),
        content: const Text(
          'This removes this player’s statistics from the match.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final success = await ref
        .read(matchManagementControllerProvider.notifier)
        .deletePerformance(widget.match.id, widget.player.id);
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop();
    } else {
      _showMessage('Could not remove match statistics.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(matchManagementControllerProvider).isLoading;
    final goalkeeper = _position == PlayerPosition.goalkeeper;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.player.name),
        actions: [
          if (_existing != null)
            IconButton(
              onPressed: saving ? null : _delete,
              tooltip: 'Remove statistics',
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'vs ${widget.match.opponent} · ${widget.match.scoreLabel}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<PlayerPosition>(
              initialValue: _position,
              decoration: const InputDecoration(labelText: 'Match position'),
              items: PlayerPosition.values
                  .map(
                    (position) => DropdownMenuItem(
                      value: position,
                      child: Text(position.labelWithCode),
                    ),
                  )
                  .toList(growable: false),
              validator: (value) => value == null ? 'Select a position.' : null,
              onChanged: saving
                  ? null
                  : (value) => setState(() => _position = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Started the match'),
              value: _starter,
              onChanged: saving
                  ? null
                  : (value) => setState(() => _starter = value),
            ),
            _section(context, 'Playing Time & Rating', [
              _field('minutes', 'Minutes played', max: 180),
              TextFormField(
                controller: _rating,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Coach rating (0–10)',
                ),
                validator: (value) {
                  final rating = double.tryParse(value ?? '');
                  return rating == null || rating < 0 || rating > 10
                      ? 'Use a rating from 0 to 10.'
                      : null;
                },
              ),
            ]),
            _section(context, 'Attacking', [
              _field('goals', 'Goals'),
              _field('assists', 'Assists'),
              _field('shots', 'Shots'),
              _field('shotsOnTarget', 'Shots on target'),
            ]),
            _section(context, 'Passing & Defending', [
              _field('passesAttempted', 'Passes attempted'),
              _field('passesCompleted', 'Passes completed'),
              _field('tackles', 'Tackles'),
              _field('interceptions', 'Interceptions'),
            ]),
            _section(context, 'Discipline', [
              _field('yellowCards', 'Yellow cards', max: 2),
              _field('redCards', 'Red cards', max: 1),
            ]),
            if (goalkeeper)
              _section(context, 'Goalkeeping', [
                _field('saves', 'Saves'),
                _field('goalsConceded', 'Goals conceded'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Clean sheet'),
                  value: _cleanSheet,
                  onChanged: saving
                      ? null
                      : (value) => setState(() => _cleanSheet = value),
                ),
              ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              minLines: 3,
              maxLines: 5,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Coach notes (optional)',
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
                  : const Icon(Icons.save_outlined),
              label: Text(saving ? 'Saving…' : 'Save Statistics'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> fields) =>
      Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 720
                    ? 3
                    : constraints.maxWidth >= 440
                    ? 2
                    : 1;
                const spacing = 10.0;
                final fieldWidth =
                    (constraints.maxWidth - (spacing * (columns - 1))) /
                    columns;
                return Wrap(
                  key: Key('performance-fields-columns-$columns'),
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final field in fields)
                      SizedBox(width: fieldWidth, child: field),
                  ],
                );
              },
            ),
          ],
        ),
      );

  Widget _field(String key, String label, {int max = 999}) => TextFormField(
    controller: _numbers[key],
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
    validator: (value) {
      final number = int.tryParse(value ?? '');
      if (number == null || number < 0 || number > max) {
        return 'Use 0–$max.';
      }
      return null;
    },
  );
}
