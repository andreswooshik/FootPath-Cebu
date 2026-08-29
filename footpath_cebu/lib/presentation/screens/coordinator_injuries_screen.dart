import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/injury_record.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/injury_providers.dart';
import 'package:footpath_cebu/presentation/screens/injury_history_screen.dart';
import 'package:footpath_cebu/presentation/widgets/adaptive_form_modal.dart';
import 'package:footpath_cebu/presentation/widgets/app_status_chip.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/injury_status_chip.dart';
import 'package:footpath_cebu/presentation/widgets/responsive_content.dart';

class CoordinatorInjuriesScreen extends ConsumerStatefulWidget {
  const CoordinatorInjuriesScreen({super.key});

  @override
  ConsumerState<CoordinatorInjuriesScreen> createState() =>
      _CoordinatorInjuriesScreenState();
}

class _CoordinatorInjuriesScreenState
    extends ConsumerState<CoordinatorInjuriesScreen> {
  String? _busyRecordId;

  Future<void> _openReport(
    BuildContext context, {
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
      final selected = await showAdaptiveFormModal<InjuryPlayerOption>(
        context: context,
        phoneHeightFactor: 0.85,
        builder: (_) => _PlayerPicker(players: players),
      );
      playerId = selected?.id;
    }
    if (playerId == null || !context.mounted) return;
    await showAdaptiveFormModal<void>(
      context: context,
      phoneHeightFactor: 0.92,
      builder: (_) =>
          InjuryReportFormSheet(playerId: playerId!, existing: existing),
    );
  }

  Future<String?> _rejectionReason(BuildContext context, String title) async {
    return showAdaptiveFormModal<String>(
      context: context,
      builder: (_) => _RequiredReasonForm(title: title),
    );
  }

  Future<T> _trackRecord<T>(
    InjuryRecord record,
    Future<T> Function() action,
  ) async {
    setState(() => _busyRecordId = record.id ?? record.playerId);
    try {
      return await action();
    } finally {
      if (mounted) setState(() => _busyRecordId = null);
    }
  }

  Future<void> _reviewReport(
    BuildContext context,
    InjuryRecord record, {
    required bool confirm,
  }) async {
    final reason = confirm
        ? ''
        : await _rejectionReason(context, 'Reject injury report');
    if (!confirm && reason == null) return;
    final ok = await _trackRecord(
      record,
      () => ref
          .read(injuryFormControllerProvider.notifier)
          .reviewReport(
            record,
            confirm: confirm,
            rejectionReason: reason ?? '',
          ),
    );
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
    InjuryRecord record, {
    required bool approve,
  }) async {
    final reason = approve
        ? ''
        : await _rejectionReason(context, 'Reject recovery update');
    if (!approve && reason == null) return;
    final ok = await _trackRecord(
      record,
      () => ref
          .read(injuryFormControllerProvider.notifier)
          .reviewStatus(
            record,
            approve: approve,
            rejectionReason: reason ?? '',
          ),
    );
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

  Future<void> _archive(BuildContext context, InjuryRecord record) async {
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
    final ok = await _trackRecord(
      record,
      () => ref.read(injuryFormControllerProvider.notifier).archive(record),
    );
    if (context.mounted) {
      _message(context, ok ? 'Injury report archived.' : 'Could not archive.');
    }
  }

  void _message(BuildContext context, String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(clubInjuriesProvider);
    final saving = ref.watch(injuryFormControllerProvider).isLoading;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Injuries'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: saving ? null : () => _openReport(context),
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
          child: ResponsiveContent(
            child: rows.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      DashboardEmptyState(
                        icon: Icons.health_and_safety_outlined,
                        title: 'No injury reports need attention',
                        message:
                            'New reports and recovery requests will appear here for review.',
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
                      final recordKey = record.id ?? record.playerId;
                      final recordSaving = _busyRecordId == recordKey;
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
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                record.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              _ReportBadge(status: record.reviewStatus),
                            ],
                          ),
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
                              if (record
                                      .pendingStatusUpdate!
                                      .notes
                                      ?.isNotEmpty ==
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
                                    onPressed: recordSaving
                                        ? null
                                        : () => _reviewReport(
                                            context,
                                            record,
                                            confirm: true,
                                          ),
                                    icon: recordSaving
                                        ? const _ActionProgress()
                                        : const Icon(Icons.check),
                                    label: const Text('Confirm'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: recordSaving
                                        ? null
                                        : () => _reviewReport(
                                            context,
                                            record,
                                            confirm: false,
                                          ),
                                    icon: const Icon(Icons.close),
                                    label: const Text('Reject'),
                                  ),
                                ],
                                if (record.pendingStatusUpdate != null) ...[
                                  FilledButton.icon(
                                    onPressed: recordSaving
                                        ? null
                                        : () => _reviewStatus(
                                            context,
                                            record,
                                            approve: true,
                                          ),
                                    icon: recordSaving
                                        ? const _ActionProgress()
                                        : const Icon(Icons.check),
                                    label: const Text('Approve update'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: recordSaving
                                        ? null
                                        : () => _reviewStatus(
                                            context,
                                            record,
                                            approve: false,
                                          ),
                                    icon: const Icon(Icons.close),
                                    label: const Text('Reject update'),
                                  ),
                                ],
                                if (record.canEditConfirmed)
                                  OutlinedButton.icon(
                                    onPressed: recordSaving
                                        ? null
                                        : () => _openReport(
                                            context,
                                            existing: record,
                                          ),
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Edit'),
                                  ),
                                if (record.canArchive)
                                  TextButton.icon(
                                    onPressed: recordSaving
                                        ? null
                                        : () => _archive(context, record),
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
      ),
    );
  }
}

class _ReportBadge extends StatelessWidget {
  const _ReportBadge({required this.status});

  final InjuryReportStatus status;

  @override
  Widget build(BuildContext context) {
    final (tone, icon) = switch (status) {
      InjuryReportStatus.pending => (
        AppStatusTone.pending,
        Icons.schedule_outlined,
      ),
      InjuryReportStatus.confirmed => (
        AppStatusTone.success,
        Icons.verified_outlined,
      ),
      InjuryReportStatus.rejected => (
        AppStatusTone.danger,
        Icons.cancel_outlined,
      ),
      InjuryReportStatus.archived => (
        AppStatusTone.neutral,
        Icons.archive_outlined,
      ),
    };
    return AppStatusChip(label: status.label, tone: tone, icon: icon);
  }
}

class _ActionProgress extends StatelessWidget {
  const _ActionProgress();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

class _PlayerPicker extends StatefulWidget {
  const _PlayerPicker({required this.players});

  final List<InjuryPlayerOption> players;

  @override
  State<_PlayerPicker> createState() => _PlayerPickerState();
}

class _PlayerPickerState extends State<_PlayerPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final players = widget.players
        .where(
          (player) =>
              query.isEmpty ||
              player.name.toLowerCase().contains(query) ||
              player.ageTier.toLowerCase().contains(query),
        )
        .toList(growable: false);
    return Padding(
      key: const Key('injury-player-picker'),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Choose player', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _search,
            autofocus: widget.players.length > 6,
            decoration: const InputDecoration(
              labelText: 'Search players',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: players.isEmpty
                ? const SingleChildScrollView(
                    child: DashboardEmptyState(
                      icon: Icons.person_search_outlined,
                      title: 'No players found',
                      message: 'Try a different player name or age tier.',
                      compact: true,
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: players.length,
                    itemBuilder: (context, index) {
                      final player = players[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            player.name.isEmpty
                                ? '?'
                                : player.name[0].toUpperCase(),
                          ),
                        ),
                        title: Text(player.name),
                        subtitle: Text(player.ageTier),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).pop(player),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequiredReasonForm extends StatefulWidget {
  const _RequiredReasonForm({required this.title});

  final String title;

  @override
  State<_RequiredReasonForm> createState() => _RequiredReasonFormState();
}

class _RequiredReasonFormState extends State<_RequiredReasonForm> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextFormField(
            controller: _controller,
            autofocus: true,
            maxLength: 500,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Reason',
              alignLabelWithHint: true,
            ),
            validator: (value) => (value ?? '').trim().isEmpty
                ? 'Enter a reason before submitting.'
                : null,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (!(_formKey.currentState?.validate() ?? false)) return;
                  Navigator.of(context).pop(_controller.text.trim());
                },
                child: const Text('Submit'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
