import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/eligibility_change.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/presentation/providers/eligibility_history_providers.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/eligibility_badge.dart';

/// One player's academic-eligibility timeline, reached from the Player and
/// Guardian dashboards or a Coordinator's player profile.
///
/// History rows are always written server-side. School-affiliated club
/// Coordinators may initiate a status change; families retain their read-only
/// view and see only the acting role, never a staff member's name.
class EligibilityHistoryScreen extends ConsumerWidget {
  const EligibilityHistoryScreen({
    super.key,
    required this.playerId,
    required this.playerName,
    this.canUpdate = false,
    this.currentStatus,
  });

  final String playerId;
  final String playerName;
  final bool canUpdate;
  final EligibilityStatus? currentStatus;

  Future<void> _chooseStatus(BuildContext context, WidgetRef ref) async {
    final selected = await showModalBottomSheet<EligibilityStatus>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EligibilityPicker(current: currentStatus),
    );
    if (selected == null || !context.mounted || selected == currentStatus) {
      return;
    }
    final saved = await ref
        .read(eligibilityUpdateControllerProvider.notifier)
        .submit(playerId, selected);
    if (!context.mounted) return;
    if (saved == null) {
      final error = ref.read(eligibilityUpdateControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              error,
              'Could not update academic eligibility.',
            ),
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(eligibilityHistoryProvider(playerId));
    final isSaving = ref.watch(eligibilityUpdateControllerProvider).isLoading;
    return Scaffold(
      appBar: AppBar(
        title: Text('Eligibility · $playerName'),
        actions: [
          if (canUpdate)
            IconButton(
              tooltip: 'Update eligibility',
              icon: isSaving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.edit_outlined),
              onPressed: isSaving ? null : () => _chooseStatus(context, ref),
            ),
        ],
      ),
      body: historyAsync.when(
        loading: () => const DashboardLoadingState(),
        error: (e, _) => DashboardErrorState(
          message: friendlyErrorMessage(
            e,
            'Something went wrong loading the eligibility history.',
          ),
          onRetry: () => ref.invalidate(eligibilityHistoryProvider(playerId)),
        ),
        data: (changes) {
          final displayedStatus =
              currentStatus ??
              (changes.isNotEmpty ? changes.first.newStatus : null);
          return RefreshIndicator(
            onRefresh: () =>
                ref.refresh(eligibilityHistoryProvider(playerId).future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _CurrentEligibility(
                  status: displayedStatus,
                  canUpdate: canUpdate,
                  isSaving: isSaving,
                  onUpdate: () => _chooseStatus(context, ref),
                ),
                const SizedBox(height: 24),
                Text(
                  'Status history',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (changes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      'No status changes yet. The timeline fills in when an '
                      'authorized club representative updates eligibility.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  for (var index = 0; index < changes.length; index++) ...[
                    if (index > 0) const SizedBox(height: 8),
                    _ChangeCard(change: changes[index]).animateListItem(
                      key: ValueKey('$playerId-$index'),
                      index: index,
                    ),
                  ],
              ],
            ),
          );
        },
      ),
    ).animateScreenEntrance();
  }
}

class _CurrentEligibility extends StatelessWidget {
  const _CurrentEligibility({
    required this.status,
    required this.canUpdate,
    required this.isSaving,
    required this.onUpdate,
  });

  final EligibilityStatus? status;
  final bool canUpdate;
  final bool isSaving;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current academic eligibility',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          if (status == null)
            const Text('No current status is available.')
          else ...[
            EligibilityBadge(status: status!),
            const SizedBox(height: 8),
            Text(eligibilityStatusMessage(status!)),
          ],
          if (canUpdate) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isSaving ? null : onUpdate,
                icon: isSaving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.edit_outlined),
                label: Text(isSaving ? 'Saving...' : 'Update eligibility'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One transition: old → new status, when, and by whom (role or name — the
/// server decides what the viewer may see).
class _ChangeCard extends StatelessWidget {
  const _ChangeCard({required this.change});

  final EligibilityChange change;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (change.oldStatus != null) ...[
                  EligibilityBadge(status: change.oldStatus!),
                  Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                ],
                EligibilityBadge(status: change.newStatus),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${formatFullDate(change.changedAt)} · by ${change.changedBy}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EligibilityPicker extends StatefulWidget {
  const _EligibilityPicker({this.current});

  final EligibilityStatus? current;

  @override
  State<_EligibilityPicker> createState() => _EligibilityPickerState();
}

class _EligibilityPickerState extends State<_EligibilityPicker> {
  EligibilityStatus? selected;

  @override
  void initState() {
    super.initState();
    selected = widget.current;
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Update academic eligibility',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Only use an approved school eligibility decision.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          RadioGroup<EligibilityStatus>(
            groupValue: selected,
            onChanged: (value) => setState(() => selected = value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final status in const [
                  EligibilityStatus.eligible,
                  EligibilityStatus.notEligible,
                  EligibilityStatus.academicWarning,
                ])
                  RadioListTile<EligibilityStatus>(
                    value: status,
                    title: Text(status.label),
                    subtitle: Text(eligibilityStatusMessage(status)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: selected == null || selected == widget.current
                    ? null
                    : () => Navigator.of(context).pop(selected),
                child: const Text('Save status'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
