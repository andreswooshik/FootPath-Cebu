import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/injury_record.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/injury_providers.dart';
import 'package:footpath_cebu/presentation/screens/injury_history_screen.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/injury_status_chip.dart';

class CoordinatorInjuriesScreen extends ConsumerWidget {
  const CoordinatorInjuriesScreen({super.key});

  Future<void> _openReport(
    BuildContext context,
    WidgetRef ref, {
    InjuryRecord? existing,
  }) async {
    var playerId = existing?.playerId;
    if (playerId == null) {
      late final List<InjuryPlayerOption> players;
      try {
        players = await ref.read(injuryReportablePlayersProvider.future);
      } catch (error) {
        if (context.mounted) {
          _message(
            context,
            friendlyErrorMessage(error, 'Could not load the player list.'),
          );
        }
        return;
      }
      if (!context.mounted) return;
      final selected = await showDialog<InjuryPlayerOption>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Choose player'),
          children: [
            if (players.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No active players are registered.'),
              )
            else
              for (final player in players)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(dialogContext).pop(player),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(player.name),
                    subtitle: Text(player.ageTier),
                  ),
                ),
          ],
        ),
      );
      playerId = selected?.id;
    }
    if (playerId == null || !context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: InjuryReportFormSheet(playerId: playerId!, existing: existing),
      ),
    );
  }

  Future<String?> _rejectionReason(BuildContext context, String title) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 500,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Reason *',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.of(dialogContext).pop(value);
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    controller.dispose();
    return reason;
  }

  Future<void> _reviewReport(
    BuildContext context,
    WidgetRef ref,
    InjuryRecord record, {
    required bool confirm,
  }) async {
    final reason = confirm
        ? ''
        : await _rejectionReason(context, 'Reject injury report');
    if (!confirm && reason == null) return;
    final ok = await ref
        .read(injuryFormControllerProvider.notifier)
        .reviewReport(record, confirm: confirm, rejectionReason: reason ?? '');
    if (!context.mounted) return;
    _message(
      context,
      ok
          ? confirm
                ? 'Injury report confirmed.'
                : 'Injury report rejected.'
          : 'Could not review the injury report.',
    );
  }

  Future<void> _reviewStatus(
    BuildContext context,
    WidgetRef ref,
    InjuryRecord record, {
    required bool approve,
  }) async {
    final reason = approve
        ? ''
        : await _rejectionReason(context, 'Reject recovery update');
    if (!approve && reason == null) return;
    final ok = await ref
        .read(injuryFormControllerProvider.notifier)
        .reviewStatus(record, approve: approve, rejectionReason: reason ?? '');
    if (!context.mounted) return;
    _message(
      context,
      ok
          ? approve
                ? 'Recovery update approved.'
                : 'Recovery update rejected.'
          : 'Could not review the recovery update.',
    );
  }

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    InjuryRecord record,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive injury report?'),
        content: const Text(
          'The report leaves the active care-team list but remains in the audit history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await ref
        .read(injuryFormControllerProvider.notifier)
        .archive(record);
    if (context.mounted) {
      _message(context, ok ? 'Injury report archived.' : 'Could not archive.');
    }
  }

  void _message(BuildContext context, String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(clubInjuriesProvider);
    final saving = ref.watch(injuryFormControllerProvider).isLoading;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Injuries'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: saving ? null : () => _openReport(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Report injury'),
      ),
      body: records.when(
        loading: () => const DashboardLoadingState(),
        error: (error, _) => DashboardErrorState(
          message: friendlyErrorMessage(error, 'Could not load injuries.'),
          onRetry: () => ref.invalidate(clubInjuriesProvider),
        ),
        data: (rows) => RefreshIndicator(
          onRefresh: () => ref.refresh(clubInjuriesProvider.future),
          child: rows.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(32),
                  children: const [
                    SizedBox(height: 72),
                    Icon(Icons.health_and_safety_outlined, size: 64),
                    SizedBox(height: 16),
                    Text(
                      'No injury reports need attention.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final record = rows[index];
                    return Card(
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          child: Text(
                            record.playerName.isEmpty
                                ? '?'
                                : record.playerName[0],
                          ),
                        ),
                        title: Text(
                          record.playerName.isEmpty
                              ? 'Player ${record.playerId}'
                              : record.playerName,
                        ),
                        subtitle: Text(record.description),
                        trailing: _ReportBadge(status: record.reviewStatus),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              InjuryStatusChip(status: record.status),
                              Text(formatFullDate(record.occurredOn)),
                              if (record.reporterName.isNotEmpty)
                                Text('Reported by ${record.reporterName}'),
                            ],
                          ),
                          if (record.notes?.isNotEmpty == true) ...[
                            const SizedBox(height: 10),
                            Text(record.notes!),
                          ],
                          if (record.pendingStatusUpdate != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Recovery request: ${record.pendingStatusUpdate!.proposedStatus.label}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (record.pendingStatusUpdate!.notes?.isNotEmpty ==
                                true)
                              Text(record.pendingStatusUpdate!.notes!),
                          ],
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            children: [
                              if (record.canReview) ...[
                                FilledButton.icon(
                                  onPressed: saving
                                      ? null
                                      : () => _reviewReport(
                                          context,
                                          ref,
                                          record,
                                          confirm: true,
                                        ),
                                  icon: const Icon(Icons.check),
                                  label: const Text('Confirm'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: saving
                                      ? null
                                      : () => _reviewReport(
                                          context,
                                          ref,
                                          record,
                                          confirm: false,
                                        ),
                                  icon: const Icon(Icons.close),
                                  label: const Text('Reject'),
                                ),
                              ],
                              if (record.pendingStatusUpdate != null) ...[
                                FilledButton.icon(
                                  onPressed: saving
                                      ? null
                                      : () => _reviewStatus(
                                          context,
                                          ref,
                                          record,
                                          approve: true,
                                        ),
                                  icon: const Icon(Icons.check),
                                  label: const Text('Approve update'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: saving
                                      ? null
                                      : () => _reviewStatus(
                                          context,
                                          ref,
                                          record,
                                          approve: false,
                                        ),
                                  icon: const Icon(Icons.close),
                                  label: const Text('Reject update'),
                                ),
                              ],
                              if (record.canEditConfirmed)
                                OutlinedButton.icon(
                                  onPressed: saving
                                      ? null
                                      : () => _openReport(
                                          context,
                                          ref,
                                          existing: record,
                                        ),
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Edit'),
                                ),
                              if (record.canArchive)
                                TextButton.icon(
                                  onPressed: saving
                                      ? null
                                      : () => _archive(context, ref, record),
                                  icon: const Icon(Icons.archive_outlined),
                                  label: const Text('Archive'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _ReportBadge extends StatelessWidget {
  const _ReportBadge({required this.status});

  final InjuryReportStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      InjuryReportStatus.pending => Colors.orange,
      InjuryReportStatus.confirmed => Colors.green,
      InjuryReportStatus.rejected => Theme.of(context).colorScheme.error,
      InjuryReportStatus.archived => Colors.grey,
    };
    return Chip(
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: 0.5)),
      label: Text(status.label),
    );
  }
}
