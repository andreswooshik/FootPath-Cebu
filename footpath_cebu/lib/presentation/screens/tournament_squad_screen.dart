import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/domain/entities/tournament_roster.dart';
import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/tournament_roster_providers.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';

const _positionCodes = [
  'GK',
  'CB',
  'LB',
  'RB',
  'CDM',
  'CM',
  'CAM',
  'LW',
  'RW',
  'ST',
];

class TournamentSquadScreen extends ConsumerStatefulWidget {
  const TournamentSquadScreen({
    super.key,
    required this.tournamentTitle,
    required this.tournamentPublished,
    required this.bracket,
    required this.canEdit,
  });

  final String tournamentTitle;
  final bool tournamentPublished;
  final TournamentAgeBracket bracket;
  final bool canEdit;

  @override
  ConsumerState<TournamentSquadScreen> createState() =>
      _TournamentSquadScreenState();
}

class _TournamentSquadScreenState extends ConsumerState<TournamentSquadScreen> {
  late TournamentSquad _squad =
      widget.bracket.squad ??
      TournamentSquad(
        id: null,
        bracketId: widget.bracket.id,
        status: TournamentSquadStatus.draft,
        entries: const [],
      );
  late final Set<String> _selected = {
    for (final entry in _squad.entries) entry.playerId,
  };
  late final Map<String, String> _positions = {
    for (final entry in _squad.entries)
      entry.playerId: entry.tournamentPosition,
  };
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<TournamentRosterSelection> get _selections {
    final ids = _selected.toList()..sort();
    return ids
        .map(
          (id) => TournamentRosterSelection(
            playerId: id,
            position: _positions[id] ?? '',
          ),
        )
        .toList(growable: false);
  }

  Future<void> _save({required bool publish}) async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one eligible player.')),
      );
      return;
    }
    final controller = ref.read(
      tournamentRosterManagementControllerProvider.notifier,
    );
    var saved = await controller.save(widget.bracket.id, _selections);
    if (!mounted) return;
    if (saved == null) {
      _showError('Could not save the tournament roster.');
      return;
    }
    if (publish) {
      saved = await controller.publish(widget.bracket.id);
      if (!mounted) return;
      if (saved == null) {
        _showError('The draft was saved, but it could not be published.');
        return;
      }
    }
    setState(() => _squad = saved!);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          publish ? 'Roster published to the club.' : 'Roster draft saved.',
        ),
      ),
    );
  }

  void _showError(String fallback) {
    final error = ref.read(tournamentRosterManagementControllerProvider).error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyErrorMessage(error, fallback))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = ref.watch(
      tournamentRosterManagementControllerProvider.select(
        (state) => state.isLoading,
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text('${widget.bracket.label} roster')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: widget.canEdit
              ? _buildCoachEditor(context, isSaving)
              : _buildReadOnly(context),
        ),
      ),
    );
  }

  Widget _buildReadOnly(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _RosterHeader(
        tournamentTitle: widget.tournamentTitle,
        bracketLabel: widget.bracket.label,
        squad: _squad,
      ),
      const SizedBox(height: 16),
      if (_squad.entries.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('The Coach has not added roster members yet.'),
          ),
        )
      else
        for (final entry in _squad.entries)
          Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text(
                  entry.playerName.trim().isEmpty
                      ? '?'
                      : entry.playerName.trim()[0].toUpperCase(),
                ),
              ),
              title: Text(entry.playerName),
              subtitle: Text(
                entry.tournamentPosition.isEmpty
                    ? 'Tournament position not assigned'
                    : entry.tournamentPosition,
              ),
              trailing: entry.isUnavailable
                  ? Tooltip(
                      message: entry.availabilityReason ?? 'Unavailable',
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    )
                  : null,
            ),
          ),
    ],
  );

  Widget _buildCoachEditor(BuildContext context, bool isSaving) {
    final candidates = ref.watch(
      tournamentRosterCandidatesProvider(widget.bracket.id),
    );
    return candidates.when(
      loading: () => const DashboardLoadingState(),
      error: (error, _) => DashboardErrorState(
        message: friendlyErrorMessage(
          error,
          'Could not load eligible players.',
        ),
        onRetry: () => ref.invalidate(
          tournamentRosterCandidatesProvider(widget.bracket.id),
        ),
      ),
      data: (rows) {
        final filtered = rows
            .where((candidate) {
              final query = _query.trim().toLowerCase();
              if (query.isEmpty) return true;
              return candidate.playerName.toLowerCase().contains(query) ||
                  candidate.currentPosition.toLowerCase().contains(query);
            })
            .toList(growable: false);
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            _RosterHeader(
              tournamentTitle: widget.tournamentTitle,
              bracketLabel: widget.bracket.label,
              squad: _squad,
            ),
            if (!widget.tournamentPublished) ...[
              const SizedBox(height: 12),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Draft preparation is open'),
                  subtitle: Text(
                    'You can save this roster now. Publishing becomes available after the Coordinator publishes the tournament.',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Search player or position',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${_selected.length} selected',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final candidate in filtered)
              _CandidateCard(
                candidate: candidate,
                selected: _selected.contains(candidate.playerId),
                position: _positions[candidate.playerId] ?? '',
                enabled: !isSaving,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selected.add(candidate.playerId);
                      _positions.putIfAbsent(
                        candidate.playerId,
                        () => candidate.tournamentPosition.isNotEmpty
                            ? candidate.tournamentPosition
                            : candidate.currentPosition,
                      );
                    } else {
                      _selected.remove(candidate.playerId);
                      _positions.remove(candidate.playerId);
                    }
                  });
                },
                onPositionChanged: (position) => setState(
                  () => _positions[candidate.playerId] = position ?? '',
                ),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: isSaving ? null : () => _save(publish: false),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    _squad.status == TournamentSquadStatus.published
                        ? 'Save roster changes'
                        : 'Save draft',
                  ),
                ),
                FilledButton.icon(
                  onPressed: isSaving || !widget.tournamentPublished
                      ? null
                      : () => _save(publish: true),
                  icon: const Icon(Icons.publish_outlined),
                  label: const Text('Publish roster'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _RosterHeader extends StatelessWidget {
  const _RosterHeader({
    required this.tournamentTitle,
    required this.bracketLabel,
    required this.squad,
  });

  final String tournamentTitle;
  final String bracketLabel;
  final TournamentSquad squad;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const CircleAvatar(child: Icon(Icons.groups_outlined)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tournamentTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('$bracketLabel - ${squad.entries.length} players'),
              ],
            ),
          ),
          Chip(label: Text(squad.status.label)),
        ],
      ),
    ),
  );
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.selected,
    required this.position,
    required this.enabled,
    required this.onSelected,
    required this.onPositionChanged,
  });

  final TournamentRosterCandidate candidate;
  final bool selected;
  final String position;
  final bool enabled;
  final ValueChanged<bool> onSelected;
  final ValueChanged<String?> onPositionChanged;

  @override
  Widget build(BuildContext context) {
    final blocked =
        candidate.eligibility == TournamentCandidateEligibility.blocked;
    final warning =
        candidate.eligibility == TournamentCandidateEligibility.warning;
    return Card(
      child: Column(
        children: [
          CheckboxListTile(
            value: selected,
            onChanged: !enabled || (blocked && !selected)
                ? null
                : (value) => onSelected(value ?? false),
            secondary: Icon(
              blocked
                  ? Icons.block_outlined
                  : warning
                  ? Icons.warning_amber_rounded
                  : Icons.check_circle_outline,
              color: blocked
                  ? Theme.of(context).colorScheme.error
                  : warning
                  ? Colors.orange.shade800
                  : Colors.green.shade700,
            ),
            title: Text(candidate.playerName),
            subtitle: Text(
              '${candidate.currentPosition.isEmpty ? 'Position unassigned' : candidate.currentPosition}\n${candidate.eligibilityReason}',
            ),
            isThreeLine: true,
          ),
          if (selected) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: DropdownButtonFormField<String>(
                initialValue: _positionCodes.contains(position) ? position : '',
                decoration: const InputDecoration(
                  labelText: 'Tournament position (optional)',
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Not assigned'),
                  ),
                  for (final code in _positionCodes)
                    DropdownMenuItem(value: code, child: Text(code)),
                ],
                onChanged: enabled ? onPositionChanged : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
