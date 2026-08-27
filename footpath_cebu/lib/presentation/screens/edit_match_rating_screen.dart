import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/match_performance.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/match_providers.dart';

class EditMatchRatingScreen extends ConsumerStatefulWidget {
  const EditMatchRatingScreen({
    super.key,
    required this.match,
    required this.player,
  });

  final FootballMatch match;
  final MatchRosterPlayer player;

  @override
  ConsumerState<EditMatchRatingScreen> createState() =>
      _EditMatchRatingScreenState();
}

class _EditMatchRatingScreenState extends ConsumerState<EditMatchRatingScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _rating = TextEditingController(
    text: widget.player.performance?.coachRating?.toStringAsFixed(1) ?? '5.0',
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.player.performance?.notes ?? '',
  );

  @override
  void dispose() {
    _rating.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final saved = await ref
        .read(matchManagementControllerProvider.notifier)
        .saveRating(
          widget.match.id,
          widget.player.id,
          MatchRatingDraft(
            coachRating: double.parse(_rating.text),
            notes: _notes.text,
          ),
        );
    if (!mounted) return;
    if (saved != null) {
      Navigator.of(context).pop(saved);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          friendlyErrorMessage(
            ref.read(matchManagementControllerProvider).error,
            'Could not save the Coach rating.',
          ),
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Coach rating?'),
        content: const Text(
          'The Coordinator statistics remain available. You can add a new rating later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep rating'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove rating'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await ref
        .read(matchManagementControllerProvider.notifier)
        .deleteRating(widget.match.id, widget.player.id);
    if (!mounted) return;
    if (removed) {
      Navigator.of(context).pop();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not remove the Coach rating.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(matchManagementControllerProvider).isLoading;
    return Scaffold(
      appBar: AppBar(
        title: Text('Rate ${widget.player.name}'),
        actions: [
          if (widget.player.ratingStatus == MatchRatingStatus.rated)
            IconButton(
              onPressed: saving ? null : _delete,
              tooltip: 'Remove Coach rating',
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.sports_soccer),
                title: Text('vs ${widget.match.opponent}'),
                subtitle: Text(
                  '${widget.player.performance!.minutesPlayed} minutes · '
                  '${widget.player.performance!.goals} goals · '
                  '${widget.player.performance!.assists} assists',
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _rating,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Coach rating (0–10)',
                prefixIcon: Icon(Icons.star_outline),
              ),
              validator: (value) {
                final number = double.tryParse(value ?? '');
                if (number == null || number < 0 || number > 10) {
                  return 'Use a rating from 0 to 10.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notes,
              minLines: 4,
              maxLines: 7,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Coach notes (optional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: saving ? null : _save,
              icon: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(saving ? 'Saving…' : 'Save Coach rating'),
            ),
          ],
        ),
      ),
    );
  }
}
