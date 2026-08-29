import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/injury_record.dart';
import 'package:footpath_cebu/domain/entities/match_performance.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/match_providers.dart';
import 'package:footpath_cebu/presentation/screens/edit_football_match_screen.dart';
import 'package:footpath_cebu/presentation/screens/edit_match_performance_screen.dart';
import 'package:footpath_cebu/presentation/screens/edit_match_rating_screen.dart';
import 'package:footpath_cebu/presentation/widgets/adaptive_form_modal.dart';
import 'package:footpath_cebu/presentation/widgets/app_status_chip.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/responsive_content.dart';

enum MatchRosterMode { coordinator, coach }

class MatchRosterScreen extends ConsumerStatefulWidget {
  const MatchRosterScreen({super.key, required this.match, required this.mode});

  final FootballMatch match;
  final MatchRosterMode mode;

  @override
  ConsumerState<MatchRosterScreen> createState() => _MatchRosterScreenState();
}

class _MatchRosterScreenState extends ConsumerState<MatchRosterScreen> {
  late FootballMatch _match;

  bool get _isCoordinator => widget.mode == MatchRosterMode.coordinator;

  @override
  void initState() {
    super.initState();
    _match = widget.match;
  }

  Future<void> _editMatch() async {
    final updated = await Navigator.of(context).push<FootballMatch>(
      MaterialPageRoute(
        builder: (_) => EditFootballMatchScreen(existing: _match),
      ),
    );
    if (updated != null && mounted) setState(() => _match = updated);
  }

  Future<void> _refresh() async {
    final _ = await ref.refresh(matchRosterProvider(_match.id).future);
  }

  Future<void> _addOutOfSquadPlayer() async {
    List<MatchRosterPlayer> candidates;
    try {
      candidates = await ref.read(
        outOfSquadMatchCandidatesProvider(_match.id).future,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              error,
              'Could not load eligible replacement players.',
            ),
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No eligible out-of-squad players found.'),
        ),
      );
      return;
    }
    final selection = await showAdaptiveFormModal<_SquadExceptionSelection>(
      context: context,
      phoneHeightFactor: 0.92,
      builder: (_) => _SquadExceptionSheet(candidates: candidates),
    );
    if (selection == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditMatchPerformanceScreen(
          match: _match,
          player: selection.player,
          squadOverrideReason: selection.reason,
        ),
      ),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(matchRosterProvider(_match.id));
    return Scaffold(
      appBar: AppBar(
        title: Text('vs ${_match.opponent}'),
        actions: [
          if (_isCoordinator)
            IconButton(
              onPressed: _editMatch,
              tooltip: 'Edit match result',
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: roster.when(
        loading: () => const DashboardLoadingState(),
        error: (error, _) => DashboardErrorState(
          message: friendlyErrorMessage(error, 'Could not load the roster.'),
          onRetry: () => ref.invalidate(matchRosterProvider(_match.id)),
        ),
        data: (players) => _RosterBody(
          match: _match,
          mode: widget.mode,
          players: players,
          onRefresh: _refresh,
          onAddOutOfSquad: _addOutOfSquadPlayer,
        ),
      ),
    );
  }
}

class _RosterBody extends StatelessWidget {
  const _RosterBody({
    required this.match,
    required this.mode,
    required this.players,
    required this.onRefresh,
    required this.onAddOutOfSquad,
  });

  final FootballMatch match;
  final MatchRosterMode mode;
  final List<MatchRosterPlayer> players;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onAddOutOfSquad;

  @override
  Widget build(BuildContext context) {
    final recorded = players.where((row) => row.performance != null).length;
    final rated = players
        .where((row) => row.ratingStatus == MatchRatingStatus.rated)
        .length;
    final coordinator = mode == MatchRosterMode.coordinator;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ResponsiveContent(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${match.venue.label} - '
                            '${match.competition.isEmpty ? 'Match' : match.competition}',
                          ),
                          if (match.isAgeBracketMatch) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${match.ageBracketLabel ?? 'Age bracket'} published squad',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            coordinator
                                ? '$recorded of ${players.length} players recorded'
                                : '$rated of $recorded recorded players rated',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      match.scoreLabel,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              coordinator ? 'Player Statistics' : 'Coach Ratings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              coordinator
                  ? 'Record objective match data. Coach ratings stay private and appear only as a status.'
                  : 'Rate a player after the Coordinator records their match statistics.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (coordinator && match.isAgeBracketMatch) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('add-out-of-squad-player'),
                  onPressed: onAddOutOfSquad,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Add eligible squad exception'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (players.isEmpty)
              const DashboardEmptyState(
                icon: Icons.group_off_outlined,
                title: 'No available players',
                message:
                    'Eligible players will appear here when they are available for this match.',
                compact: true,
              )
            else
              for (final player in players)
                _PlayerPerformanceTile(
                  match: match,
                  mode: mode,
                  player: player,
                  onChanged: onRefresh,
                ),
          ],
        ),
      ),
    );
  }
}

class _PlayerPerformanceTile extends StatelessWidget {
  const _PlayerPerformanceTile({
    required this.match,
    required this.mode,
    required this.player,
    required this.onChanged,
  });

  final FootballMatch match;
  final MatchRosterMode mode;
  final MatchRosterPlayer player;
  final Future<void> Function() onChanged;

  Future<void> _open(BuildContext context) async {
    if (mode == MatchRosterMode.coach && player.performance == null) return;
    if (mode == MatchRosterMode.coordinator && !player.isSelectable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            player.availabilityReason.isEmpty
                ? 'This player is not currently eligible for match selection.'
                : player.availabilityReason,
          ),
        ),
      );
      return;
    }
    var injuryOverrideAcknowledged = false;
    if (mode == MatchRosterMode.coordinator &&
        player.activeInjuryStatus != null) {
      final acknowledged = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Active injury warning'),
          content: Text(
            '${player.name} has a confirmed ${player.activeInjuryStatus!.label} injury. Continue only if the player participated; saving statistics will record this override in the audit log.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue to statistics'),
            ),
          ],
        ),
      );
      if (acknowledged != true || !context.mounted) return;
      injuryOverrideAcknowledged = true;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => mode == MatchRosterMode.coordinator
            ? EditMatchPerformanceScreen(
                match: match,
                player: player,
                existing: player.performance,
                injuryOverrideAcknowledged: injuryOverrideAcknowledged,
              )
            : EditMatchRatingScreen(match: match, player: player),
      ),
    );
    await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final saved = player.performance != null;
    final coordinator = mode == MatchRosterMode.coordinator;
    final position = saved
        ? player.performance!.position
        : player.tournamentPosition.isNotEmpty
        ? player.tournamentPosition
        : player.registeredPosition.isEmpty
        ? 'No position'
        : player.registeredPosition;
    final status = player.ratingStatus.label;
    final rating = player.performance?.coachRating;
    final injury = player.activeInjuryStatus;
    final exception =
        player.requiresSquadOverride ||
        (player.performance?.squadException ?? false);
    final warning = player.availability == 'WARNING';
    return Card(
      child: ListTile(
        onTap: coordinator || saved ? () => _open(context) : null,
        leading: CircleAvatar(
          child: Text(player.name.isEmpty ? '?' : player.name[0]),
        ),
        title: Text(player.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              coordinator
                  ? '$position - ${saved ? status : 'Not recorded'}'
                  : '$position - $status${rating == null ? '' : ' (${rating.toStringAsFixed(1)})'}',
            ),
            if (exception) ...[
              const SizedBox(height: 6),
              const AppStatusChip(
                label: 'Approved squad exception',
                tone: AppStatusTone.info,
                icon: Icons.person_add_alt_1_outlined,
              ),
            ],
            if (warning) ...[
              const SizedBox(height: 6),
              Text(
                player.availabilityReason,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                ),
              ),
            ],
            if (injury != null && coordinator) ...[
              const SizedBox(height: 6),
              AppStatusChip(
                label:
                    'Confirmed ${injury.label} injury - ${match.isAgeBracketMatch ? 'unavailable' : 'review before entry'}',
                tone: AppStatusTone.danger,
                icon: Icons.healing_outlined,
              ),
            ],
          ],
        ),
        isThreeLine: exception || warning || (coordinator && injury != null),
        trailing: Icon(
          coordinator
              ? saved
                    ? Icons.edit_outlined
                    : Icons.add_circle_outline
              : !saved
              ? Icons.hourglass_empty
              : player.ratingStatus == MatchRatingStatus.rated
              ? Icons.edit_outlined
              : Icons.star_outline,
          color: !player.isSelectable && coordinator
              ? Theme.of(context).colorScheme.error
              : saved
              ? Theme.of(context).colorScheme.primary
              : null,
        ),
      ),
    );
  }
}

class _SquadExceptionSelection {
  const _SquadExceptionSelection(this.player, this.reason);

  final MatchRosterPlayer player;
  final String reason;
}

class _SquadExceptionSheet extends StatefulWidget {
  const _SquadExceptionSheet({required this.candidates});

  final List<MatchRosterPlayer> candidates;

  @override
  State<_SquadExceptionSheet> createState() => _SquadExceptionSheetState();
}

class _SquadExceptionSheetState extends State<_SquadExceptionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _search = TextEditingController();
  final _reason = TextEditingController();
  MatchRosterPlayer? _selected;

  @override
  void dispose() {
    _search.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = widget.candidates
        .where(
          (player) =>
              query.isEmpty ||
              player.name.toLowerCase().contains(query) ||
              player.registeredPosition.toLowerCase().contains(query),
        )
        .toList(growable: false);
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 16),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SizedBox(
            height: double.infinity,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Add squad exception',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const Text(
                    'Only age- and injury-eligible players appear. The reason is stored with the match statistics and audit log.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('squad-exception-search'),
                    controller: _search,
                    decoration: const InputDecoration(
                      labelText: 'Search eligible players',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: RadioGroup<String>(
                      groupValue: _selected?.id,
                      onChanged: (playerId) => setState(
                        () => _selected = visible.firstWhere(
                          (player) => player.id == playerId,
                        ),
                      ),
                      child: ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final player = visible[index];
                          return RadioListTile<String>(
                            key: Key('squad-exception-player-${player.id}'),
                            value: player.id,
                            title: Text(player.name),
                            subtitle: Text(
                              player.availability == 'WARNING'
                                  ? player.availabilityReason
                                  : player.registeredPosition.isEmpty
                                  ? 'Position not assigned'
                                  : player.registeredPosition,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('squad-exception-reason'),
                    controller: _reason,
                    maxLength: 500,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Required exception reason',
                      hintText: 'Example: organizer-approved late replacement',
                      counterText: '',
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Enter the Coordinator exception reason.'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('continue-squad-exception'),
                      onPressed: () {
                        if (_selected == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Select a player.')),
                          );
                          return;
                        }
                        if (!_formKey.currentState!.validate()) return;
                        Navigator.of(context).pop(
                          _SquadExceptionSelection(
                            _selected!,
                            _reason.text.trim(),
                          ),
                        );
                      },
                      child: const Text('Continue to statistics'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
