import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/eligibility_change.dart';
import 'package:footpath_cebu/presentation/providers/eligibility_history_providers.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/eligibility_badge.dart';

/// One player's academic-eligibility timeline — a read-only task/detail
/// screen (no bottom nav), reached from the Player dashboard and from the
/// Guardian dashboard per linked child.
///
/// Read-only by design everywhere: history rows are written server-side when
/// School Staff/Admin change the status, never from the app. Shows who made
/// each change as the server exposes it — families see the acting role
/// ("School Staff"), never a staff member's name.
class EligibilityHistoryScreen extends ConsumerWidget {
  const EligibilityHistoryScreen({
    super.key,
    required this.playerId,
    required this.playerName,
  });

  final String playerId;
  final String playerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(eligibilityHistoryProvider(playerId));
    return Scaffold(
      appBar: AppBar(title: Text('Eligibility · $playerName')),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => DashboardErrorState(
          message: friendlyErrorMessage(
            e,
            'Something went wrong loading the eligibility history.',
          ),
          onRetry: () =>
              ref.invalidate(eligibilityHistoryProvider(playerId)),
        ),
        data: (changes) {
          if (changes.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No status changes yet. The timeline fills in as School '
                  'Staff update the academic eligibility.',
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
                  _ChangeCard(change: changes[index]),
            ),
          );
        },
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
                  Icon(Icons.arrow_forward, size: 16, color: cs.onSurfaceVariant),
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
