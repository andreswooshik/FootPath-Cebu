import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/utils/date_format.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/domain/entities/player_stats.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/player_position_controller.dart';
import 'package:footpath_cebu/presentation/providers/player_stats_providers.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';
import 'package:footpath_cebu/presentation/screens/edit_performance_data_screen.dart';
import 'package:footpath_cebu/presentation/screens/player_stats_screen.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/position_picker_sheet.dart';
import 'package:footpath_cebu/presentation/widgets/responsive_content.dart';

/// One coach-owned workspace for the two deliberately separate assessment
/// systems: position-aware 0-99 Player Stats and formal 1-5 development data.
class CoachAssessmentHubScreen extends ConsumerStatefulWidget {
  const CoachAssessmentHubScreen({
    super.key,
    required this.player,
    required this.profile,
  });

  final Player player;
  final UserProfile profile;

  @override
  ConsumerState<CoachAssessmentHubScreen> createState() =>
      _CoachAssessmentHubScreenState();
}

class _CoachAssessmentHubScreenState
    extends ConsumerState<CoachAssessmentHubScreen> {
  late Player _player = widget.player;

  void _close() => Navigator.of(context).pop(_player);

  Future<void> _editPosition() async {
    final picked = await showPositionPickerSheet(
      context: context,
      playerName: _player.name,
      current: _player.position,
    );
    if (picked == null || picked == _player.position || !mounted) return;

    final previous = _player.position;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(previous == null ? 'Assign position?' : 'Change position?'),
        content: Text(
          previous == null
              ? '${_player.name} will be assigned ${picked.labelWithCode}.'
              : '${_player.name} will change from ${previous.labelWithCode} to ${picked.labelWithCode}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(previous == null ? 'Assign' : 'Change'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final updated = await ref
        .read(playerPositionControllerProvider.notifier)
        .submit(_player.id, picked);
    if (!mounted) return;
    if (updated == null) {
      final error = ref.read(playerPositionControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(error, 'Could not update the position.'),
          ),
        ),
      );
      return;
    }

    setState(() => _player = updated);
    ref.invalidate(playerStatsProvider(_player.id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_player.name} is now ${picked.labelWithCode}.'),
      ),
    );
  }

  Future<void> _editPlayerStats(PlayerStats stats) async {
    final saved = await Navigator.of(context).push<PlayerStatsSaveResult>(
      MaterialPageRoute(
        builder: (_) => PlayerStatsAssessmentScreen(
          playerId: _player.id,
          playerName: _player.name,
          stats: stats,
        ),
      ),
    );
    if (saved == null || !mounted) return;

    setState(
      () => _player = _player.copyWith(
        latestPlayerStats: LatestPlayerStats(
          catalog: stats.catalog,
          assessment: saved.assessment,
        ),
      ),
    );
    ref.invalidate(playerStatsProvider(_player.id));
    ref.invalidate(squadProvider);
  }

  Future<void> _editDevelopment() async {
    final updated = await Navigator.of(context).push<Player>(
      MaterialPageRoute(
        builder: (_) =>
            EditPerformanceDataScreen(player: _player, profile: widget.profile),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() => _player = updated);
    ref.invalidate(squadProvider);
  }

  @override
  Widget build(BuildContext context) {
    final stats = _player.position == null
        ? null
        : ref.watch(playerStatsProvider(_player.id));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _close),
          title: const Text('Assess Player'),
        ),
        body: ResponsiveContent(
          maxWidth: 760,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _PlayerHeader(player: _player),
              const SizedBox(height: 16),
              _PositionGateCard(
                player: _player,
                saving: ref.watch(playerPositionControllerProvider).isLoading,
                onEdit: _editPosition,
              ),
              const SizedBox(height: 16),
              if (stats == null)
                const _PlayerStatsLockedCard()
              else
                stats.when(
                  loading: () => const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: DashboardLoadingState(
                        compact: true,
                        shrinkWrap: true,
                      ),
                    ),
                  ),
                  error: (error, _) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: const Text('Player Stats unavailable'),
                      subtitle: Text(
                        friendlyErrorMessage(
                          error,
                          'Could not load Player Stats.',
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: 'Retry',
                        onPressed: () =>
                            ref.invalidate(playerStatsProvider(_player.id)),
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                  ),
                  data: (value) => _PlayerStatsAssessmentCard(
                    stats: value,
                    onAssess: () => _editPlayerStats(value),
                    onHistory: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PlayerStatsScreen(
                          playerId: _player.id,
                          playerName: _player.name,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              _DevelopmentAssessmentCard(
                player: _player,
                onAssess: _editDevelopment,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerHeader extends StatelessWidget {
  const _PlayerHeader({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            foregroundImage: player.photoUrl == null
                ? null
                : NetworkImage(player.photoUrl!),
            child: player.photoUrl == null
                ? const Icon(Icons.person_outline, size: 30)
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  '${player.ageTier.label} · Age ${player.age} · ${player.classYear}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _PositionGateCard extends StatelessWidget {
  const _PositionGateCard({
    required this.player,
    required this.saving,
    required this.onEdit,
  });

  final Player player;
  final bool saving;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: ListTile(
      leading: CircleAvatar(child: Text(player.position?.code ?? '—')),
      title: Text(player.position?.labelWithCode ?? 'Position required'),
      subtitle: Text(
        player.position == null
            ? 'Assign a position before creating Player Stats.'
            : 'The position selects the correct six-attribute catalog.',
      ),
      trailing: TextButton.icon(
        key: const Key('assessment-position-action'),
        onPressed: saving ? null : onEdit,
        icon: saving
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.swap_horiz),
        label: Text(player.position == null ? 'Assign' : 'Change'),
      ),
    ),
  );
}

class _PlayerStatsLockedCard extends StatelessWidget {
  const _PlayerStatsLockedCard();

  @override
  Widget build(BuildContext context) => const Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.query_stats_outlined),
            title: Text('Card Attributes · 0–99'),
            subtitle: Text('Position-aware Player Stats'),
          ),
          Text('Assign a position to unlock the correct attribute catalog.'),
        ],
      ),
    ),
  );
}

class _PlayerStatsAssessmentCard extends StatelessWidget {
  const _PlayerStatsAssessmentCard({
    required this.stats,
    required this.onAssess,
    required this.onHistory,
  });

  final PlayerStats stats;
  final VoidCallback onAssess;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final latest = stats.latest;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                child: Text(latest?.overall.toString() ?? '—'),
              ),
              title: const Text('Card Attributes · 0–99'),
              subtitle: Text(
                latest == null
                    ? '${stats.catalog.roleGroup} · Baseline not recorded'
                    : '${stats.catalog.roleGroup} · Updated ${formatFullDate(latest.createdAt)}',
              ),
            ),
            if (latest != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final attribute in stats.catalog.attributes)
                    Chip(
                      label: Text(
                        '$attribute ${latest.scores[_statsKey(attribute)]}',
                      ),
                    ),
                ],
              )
            else
              const Text(
                'Create the first complete six-attribute snapshot for this position group.',
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onHistory,
                    icon: const Icon(Icons.history),
                    label: const Text('History'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('assess-card-attributes'),
                    onPressed: onAssess,
                    icon: const Icon(Icons.tune),
                    label: Text(
                      latest == null ? 'Create baseline' : 'Update attributes',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _statsKey(String attribute) =>
    attribute.toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');

class _DevelopmentAssessmentCard extends StatelessWidget {
  const _DevelopmentAssessmentCard({
    required this.player,
    required this.onAssess,
  });

  final Player player;
  final VoidCallback onAssess;

  @override
  Widget build(BuildContext context) {
    final assessment = player.developmentAssessment;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                child: Icon(Icons.psychology_outlined),
              ),
              title: const Text('Development Assessment · 1–5'),
              subtitle: Text(
                assessment == null
                    ? 'Five-domain assessment not recorded'
                    : 'Technical, tactical, physical, mental, and values',
              ),
            ),
            Text(
              assessment == null
                  ? 'Record current strengths and development targets independently from Player Stats.'
                  : assessment.strengths,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                key: const Key('assess-development'),
                onPressed: onAssess,
                icon: const Icon(Icons.edit_note),
                label: Text(
                  assessment == null
                      ? 'Create development assessment'
                      : 'Update development assessment',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
