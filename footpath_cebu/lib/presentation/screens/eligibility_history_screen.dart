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
          if (changes.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No status changes yet. The timeline fills in when an '
                  'authorized club representative updates eligibility.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.refresh(eligibilityHistoryProvider(playerId).future),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: changes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) =>
                  _ChangeCard(change: changes[index]).animateListItem(
                    key: ValueKey('$playerId-$index'),
                    index: index,
                  ),
            ),
          );
        },
      ),
    ).animateScreenEntrance();
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

class _EligibilityPicker extends StatelessWidget {
  const _EligibilityPicker({this.current});

  final EligibilityStatus? current;

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
            groupValue: current,
            onChanged: (value) => Navigator.of(context).pop(value),
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
        ],
      ),
    ),
  );
}
