import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/dispute.dart';
import 'package:footpath_cebu/presentation/providers/dispute_providers.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';

/// Coach Portal — every dispute with its thread, reached from the coach's
/// profile. Tapping a dispute opens the thread with a respond form.
class DisputeListScreen extends ConsumerWidget {
  const DisputeListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disputesAsync = ref.watch(disputesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Disputes')),
      body: disputesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => DashboardErrorState(
          message: friendlyErrorMessage(
            e,
            'Something went wrong loading disputes.',
          ),
          onRetry: () => ref.invalidate(disputesProvider),
        ),
        data: (disputes) {
          if (disputes.isEmpty) {
            return const Center(
              child: Text(
                'No disputes. Flag one from a player profile.',
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(disputesProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: disputes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final dispute = disputes[index];
                return Card(
                  child: ListTile(
                    title: Text(dispute.summary),
                    subtitle: Text(_subtitle(dispute)),
                    trailing: DisputeStatusChip(status: dispute.status),
                    onTap: () => _openThread(context, dispute),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  String _subtitle(Dispute dispute) {
    final parts = [
      dispute.category.label,
      if (dispute.subjectPlayerName != null) dispute.subjectPlayerName!,
      formatShortDate(dispute.createdAt),
    ];
    return parts.join(' · ');
  }

  void _openThread(BuildContext context, Dispute dispute) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _DisputeThreadSheet(dispute: dispute),
      ),
    );
  }
}

/// A colour-coded chip for a [DisputeStatus] value.
class DisputeStatusChip extends StatelessWidget {
  const DisputeStatusChip({super.key, required this.status});

  final DisputeStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      DisputeStatus.open => (Colors.red, Icons.flag_outlined),
      DisputeStatus.underReview => (Colors.orange, Icons.hourglass_top),
      DisputeStatus.resolved => (Colors.green, Icons.check_circle_outline),
      DisputeStatus.dismissed => (Colors.blueGrey, Icons.cancel_outlined),
    };
    return Chip(
      avatar: Icon(icon, color: color, size: 18),
      label: Text(status.label),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// The thread + respond form for one dispute. The dispute shown is the
/// snapshot handed in; a posted response pops the sheet and the invalidated
/// list refetches, so stale threads never linger.
class _DisputeThreadSheet extends ConsumerStatefulWidget {
  const _DisputeThreadSheet({required this.dispute});

  final Dispute dispute;

  @override
  ConsumerState<_DisputeThreadSheet> createState() =>
      _DisputeThreadSheetState();
}

class _DisputeThreadSheetState extends ConsumerState<_DisputeThreadSheet> {
  final _bodyController = TextEditingController();
  DisputeStatus? _statusChangeTo;

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _respond() async {
    final body = _bodyController.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write a response first.')),
      );
      return;
    }
    final updated =
        await ref.read(disputeFormControllerProvider.notifier).respond(
              widget.dispute.id,
              body,
              statusChangeTo: _statusChangeTo,
            );
    if (!mounted) return;
    if (updated == null) {
      final error = ref.read(disputeFormControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(error, 'Could not post the response.'),
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Response posted.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dispute = widget.dispute;
    final isSaving = ref.watch(disputeFormControllerProvider).isLoading;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(dispute.summary, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              [
                dispute.category.label,
                if (dispute.raisedByName != null)
                  'raised by ${dispute.raisedByName}',
                formatFullDate(dispute.createdAt),
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
            if (dispute.detail != null) ...[
              const SizedBox(height: 12),
              Text(dispute.detail!),
            ],
            const SizedBox(height: 16),
            Text('Thread', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (dispute.responses.isEmpty)
              const Text('No responses yet.')
            else
              for (final response in dispute.responses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          response.authorName ?? 'Unknown',
                          formatShortDate(response.createdAt),
                          if (response.statusChangeTo != null)
                            '→ ${response.statusChangeTo!.label}',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(response.body),
                    ],
                  ),
                ),
            const Divider(height: 24),
            TextField(
              controller: _bodyController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Your response',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<DisputeStatus?>(
              initialValue: _statusChangeTo,
              decoration: const InputDecoration(
                labelText: 'Change status (optional)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<DisputeStatus?>(
                  value: null,
                  child: Text('No change'),
                ),
                for (final status in DisputeStatus.values)
                  DropdownMenuItem<DisputeStatus?>(
                    value: status,
                    child: Text(status.label),
                  ),
              ],
              onChanged: (value) => setState(() => _statusChangeTo = value),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: isSaving ? null : _respond,
              child: isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Post Response'),
            ),
          ],
        ),
      ),
    );
  }
}
