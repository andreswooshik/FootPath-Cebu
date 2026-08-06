import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/domain/entities/dispute.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/presentation/providers/dispute_providers.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';

/// Coach Portal — flag a dispute about one player, reached from the flag
/// action on the player profile. A task screen: saves and pops.
class FlagDisputeScreen extends ConsumerStatefulWidget {
  const FlagDisputeScreen({super.key, required this.player});

  /// The player the dispute concerns (prefilled, not editable here — a
  /// general dispute is raised from the console/admin side instead).
  final Player player;

  @override
  ConsumerState<FlagDisputeScreen> createState() => _FlagDisputeScreenState();
}

class _FlagDisputeScreenState extends ConsumerState<FlagDisputeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _summaryController = TextEditingController();
  final _detailController = TextEditingController();
  DisputeCategory _category = DisputeCategory.attendance;

  @override
  void dispose() {
    _summaryController.dispose();
    _detailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final detail = _detailController.text.trim();
    final dispute = await ref
        .read(disputeFormControllerProvider.notifier)
        .raise(
          category: _category,
          summary: _summaryController.text.trim(),
          detail: detail.isEmpty ? null : detail,
          subjectPlayerId: widget.player.id,
        );
    if (!mounted) return;
    if (dispute == null) {
      final error = ref.read(disputeFormControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(error, 'Could not raise the dispute.'),
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Dispute raised.')));
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = ref.watch(disputeFormControllerProvider).isLoading;
    return Scaffold(
      appBar: AppBar(title: const Text('Flag Dispute')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(widget.player.name),
                subtitle: const Text('Subject of this dispute'),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<DisputeCategory>(
              initialValue: _category,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final category in DisputeCategory.values)
                  DropdownMenuItem(
                    value: category,
                    child: Text(category.label),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _category = value ?? _category),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _summaryController,
              decoration: const InputDecoration(
                labelText: 'Summary *',
                hintText: 'One line: what is being disputed?',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'A summary is required.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _detailController,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Detail',
                hintText: 'Context, dates, what you expect to happen…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: isSaving ? null : _submit,
              icon: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.flag_outlined),
              label: const Text('Raise Dispute'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    ).animateScreenEntrance();
  }
}
