import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/domain/entities/card_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/player_position_controller.dart';
import 'package:footpath_cebu/presentation/screens/edit_performance_data_screen.dart';
import 'package:footpath_cebu/presentation/screens/flag_dispute_screen.dart';
import 'package:footpath_cebu/presentation/screens/injury_history_screen.dart';
import 'package:footpath_cebu/presentation/widgets/attribute_radar_chart.dart';
import 'package:footpath_cebu/presentation/widgets/player_card.dart';
import 'package:footpath_cebu/presentation/widgets/position_picker_sheet.dart';
import 'package:footpath_cebu/presentation/widgets/tier_badge.dart';

/// Coach Portal — one player's profile, opened by tapping a card on the squad
/// roster. Shows the FUT card, the six technical attributes, the player's
/// position and academic standing, and links to the assessment form.
///
/// Holds the player locally so ratings and the position edited here are
/// reflected on the card as soon as the coach saves.
class PlayerProfileScreen extends ConsumerStatefulWidget {
  const PlayerProfileScreen({
    super.key,
    required this.player,
    required this.profile,
  });

  final Player player;

  /// The signed-in coach, forwarded to the shared bottom navigation.
  final UserProfile profile;

  @override
  ConsumerState<PlayerProfileScreen> createState() =>
      _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends ConsumerState<PlayerProfileScreen> {
  late Player _player = widget.player;

  bool get _isGoalkeeper => _player.position?.group == PositionGroup.goalkeeper;

  Future<void> _openEditor() async {
    // The editor returns the whole saved Player, not just the ratings: the
    // assessment also writes the coach's note, and popping ratings alone would
    // leave this screen showing a stale one.
    final updated = await Navigator.of(context).push<Player>(
      MaterialPageRoute(
        builder: (_) =>
            EditPerformanceDataScreen(player: _player, profile: widget.profile),
      ),
    );
    if (updated == null) return;
    setState(() => _player = updated);
  }

  /// Pick a position, confirm it, then persist it.
  ///
  /// The confirmation names the old and new position: one mis-tap in a
  /// ten-item list would otherwise silently re-label a player.
  Future<void> _editPosition() async {
    final picked = await showPositionPickerSheet(
      context: context,
      playerName: _player.name,
      current: _player.position,
    );
    if (picked == null || !mounted) return;
    if (picked == _player.position) return; // nothing changed

    final previous = _player.position;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(previous == null ? 'Assign position?' : 'Change position?'),
        content: Text(
          previous == null
              ? '${_player.name} will be assigned '
                    '${picked.labelWithCode}.'
              : '${_player.name} will change from '
                    '${previous.labelWithCode} to ${picked.labelWithCode}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_player.name} is now ${picked.labelWithCode}.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _player.ratings;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Player Profile'),
        actions: [
          // Only a coach can flag a dispute (server-enforced; hiding the
          // action for other roles is UX, not authorisation).
          if (widget.profile.isCoach)
            IconButton(
              icon: const Icon(Icons.flag_outlined),
              tooltip: 'Flag dispute',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FlagDisputeScreen(player: _player),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share',
            onPressed: () => ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Coming soon.'))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: PlayerCard(player: _player),
            ),
          ),
          const SizedBox(height: 12),
          Center(child: TierBadge(tier: CardTier.forPlayer(_player))),
          const SizedBox(height: 24),
          Text(
            'Attribute Web',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: AttributeRadarChart(
              ratings: r,
              isGoalkeeper: _isGoalkeeper,
              size: 240,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Technical Performance',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.05,
            children: _isGoalkeeper
                ? [
                    _AttributeTile(label: 'DIV', value: r.diving),
                    _AttributeTile(label: 'HAN', value: r.handling),
                    _AttributeTile(label: 'KIC', value: r.kicking),
                    _AttributeTile(label: 'REF', value: r.reflexes),
                    _AttributeTile(label: 'SPD', value: r.speed),
                    _AttributeTile(label: 'POS', value: r.positioning),
                  ]
                : [
                    _AttributeTile(label: 'PAC', value: r.pace),
                    _AttributeTile(label: 'SHO', value: r.shooting),
                    _AttributeTile(label: 'PAS', value: r.passing),
                    _AttributeTile(label: 'DRI', value: r.dribbling),
                    _AttributeTile(label: 'DEF', value: r.defending),
                    _AttributeTile(label: 'PHY', value: r.physical),
                  ],
          ),
          const SizedBox(height: 16),
          _PlayerPositionCard(
            position: _player.position,
            // Only a coach may assign a position; every other role sees the
            // same card without an action. The server must enforce this too —
            // a client-side check is UX, not authorisation.
            onEdit: widget.profile.isCoach ? _editPosition : null,
            isSaving: ref.watch(playerPositionControllerProvider).isLoading,
          ),
          const SizedBox(height: 16),
          _CoachEvaluationCard(notes: _player.coachNotes),
          const SizedBox(height: 16),
          _AcademicStandingCard(status: _player.eligibility),
          const SizedBox(height: 16),
          // Medical context for training decisions. Read-only for the coach —
          // the player owns their records (and the server enforces it).
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.healing_outlined),
              title: const Text('Injury History'),
              subtitle: const Text('View reported injuries'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => InjuryHistoryScreen(
                    playerId: _player.id,
                    playerName: _player.name,
                    readOnly: true,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _openEditor,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Update Performance Data'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}

/// The player's position — read-only for every role except the coach, who can
/// assign it (when unset) or change it.
///
/// An unassigned player is stated plainly rather than shown as a blank or a
/// placeholder code: "not yet assigned" is real information, and it's the
/// prompt for the coach to act after they've evaluated the player.
class _PlayerPositionCard extends StatelessWidget {
  const _PlayerPositionCard({
    required this.position,
    required this.onEdit,
    required this.isSaving,
  });

  final PlayerPosition? position;

  /// Null for non-coach roles, which makes the card view-only.
  final VoidCallback? onEdit;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final assigned = position != null;
    final accent = assigned ? cs.primary : cs.tertiary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            child: assigned
                ? Text(
                    position!.code,
                    style: TextStyle(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  )
                : Icon(Icons.help_outline, color: cs.onTertiary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Player Position',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  assigned ? position!.labelWithCode : 'Not yet assigned',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  assigned
                      ? 'Set by the coach'
                      : 'The coach assigns this after evaluating the player.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (onEdit != null) ...[
            const SizedBox(width: 8),
            isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : assigned
                ? TextButton(onPressed: onEdit, child: const Text('Change'))
                : FilledButton.tonal(
                    onPressed: onEdit,
                    child: const Text('Assign'),
                  ),
          ],
        ],
      ),
    );
  }
}

/// One of the six attributes: its short code, the value, and a fill bar.
class _AttributeTile extends StatelessWidget {
  const _AttributeTile({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$value',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value / 99,
                minHeight: 4,
                backgroundColor: Colors.grey.shade300,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The coach's standing written evaluation, saved with the assessment.
///
/// Always rendered, even with no note yet: an empty state tells the coach the
/// evaluation exists and is theirs to fill, where a hidden card would read as a
/// missing feature.
class _CoachEvaluationCard extends StatelessWidget {
  const _CoachEvaluationCard({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasNotes = notes.trim().isNotEmpty;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.rate_review_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Coach Evaluation',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              hasNotes ? notes : 'No written evaluation yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: hasNotes ? FontStyle.normal : FontStyle.italic,
                color: hasNotes
                    ? null
                    : theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The academic gate set by School Staff — read-only for the coach.
class _AcademicStandingCard extends StatelessWidget {
  const _AcademicStandingCard({required this.status});

  final EligibilityStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _eligibilityColor(status);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: const Icon(
              Icons.school_outlined,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Academic Standing',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _standingDescription(status),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Color _eligibilityColor(EligibilityStatus status) => switch (status) {
  EligibilityStatus.eligible => Colors.green,
  EligibilityStatus.notEligible => Colors.red,
  EligibilityStatus.pending => Colors.orange,
  EligibilityStatus.academicWarning => Colors.amber.shade800,
};

String _standingDescription(EligibilityStatus status) => switch (status) {
  EligibilityStatus.eligible => 'Eligible for National Selection',
  EligibilityStatus.notEligible => 'Not eligible for selection',
  EligibilityStatus.pending => 'Academic standing pending review',
  EligibilityStatus.academicWarning => 'Academic warning — review required',
};
