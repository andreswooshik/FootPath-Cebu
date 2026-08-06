import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/providers/edit_performance_controller.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';

/// Coach Portal — the player assessment form.
///
/// Following the same convention as the Schedule Session form, the editable
/// values live here in the View and are handed back as a draft [PlayerRatings]
/// when the coach saves. The draft is persisted through
/// [EditPerformanceController] (`PUT /api/players/<id>/assessment/`), then
/// popped so [PlayerProfileScreen] can apply the saved ratings to the card.
class EditPerformanceDataScreen extends ConsumerStatefulWidget {
  const EditPerformanceDataScreen({
    super.key,
    required this.player,
    required this.profile,
  });

  final Player player;

  /// The signed-in coach, forwarded to the shared bottom navigation.
  final UserProfile profile;

  @override
  ConsumerState<EditPerformanceDataScreen> createState() =>
      _EditPerformanceDataScreenState();
}

class _EditPerformanceDataScreenState
    extends ConsumerState<EditPerformanceDataScreen> {
  late int _pace = widget.player.ratings.pace;
  late int _shooting = widget.player.ratings.shooting;
  late int _passing = widget.player.ratings.passing;
  late int _dribbling = widget.player.ratings.dribbling;
  late int _defending = widget.player.ratings.defending;
  late int _physical = widget.player.ratings.physical;

  // GK six — seeded even for an outfield player so a later position change
  // doesn't lose whatever was on file. Only shown/edited when [_isGoalkeeper].
  late int _diving = widget.player.ratings.diving;
  late int _handling = widget.player.ratings.handling;
  late int _kicking = widget.player.ratings.kicking;
  late int _reflexes = widget.player.ratings.reflexes;
  late int _speed = widget.player.ratings.speed;
  late int _positioning = widget.player.ratings.positioning;

  /// Seeded with the note already on file so the form opens showing the
  /// current evaluation. Starting it empty would let a coach who only came to
  /// nudge a slider silently overwrite an existing note with a blank one.
  late final _notesController = TextEditingController(
    text: widget.player.coachNotes,
  );

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  bool get _isGoalkeeper =>
      widget.player.position?.group == PositionGroup.goalkeeper;

  /// The live draft. Always carries all twelve fields, not just the six shown
  /// on screen for this position — editing a GK's reflexes must not silently
  /// zero their (unedited, unseen) outfield six, and vice versa.
  PlayerRatings get _draft => PlayerRatings(
    pace: _pace,
    shooting: _shooting,
    passing: _passing,
    dribbling: _dribbling,
    defending: _defending,
    physical: _physical,
    diving: _diving,
    handling: _handling,
    kicking: _kicking,
    reflexes: _reflexes,
    speed: _speed,
    positioning: _positioning,
  );

  /// The header badge's live number as sliders move — position-aware via
  /// [Player.overall], so this screen doesn't re-implement that branch.
  int get _draftOverall => widget.player.copyWith(ratings: _draft).overall;

  Future<void> _save() async {
    final saved = await ref
        .read(editPerformanceControllerProvider.notifier)
        .submit(
          widget.player.id,
          _draft,
          coachNotes: _notesController.text.trim(),
        );
    if (!mounted) return;
    if (saved != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Assessment saved for ${widget.player.name}.')),
      );
      Navigator.of(context).pop(saved);
    } else {
      final error = ref.read(editPerformanceControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              error,
              'Could not save the assessment. Please try again.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSaving = ref.watch(editPerformanceControllerProvider).isLoading;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Update Performance Data'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _Avatar(player: widget.player, radius: 16),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PlayerHeader(player: widget.player, overall: _draftOverall),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'Technical Attributes',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                'FUT STANDARD SCALING',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.grey.shade600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_isGoalkeeper) ...[
            _AttributeSlider(
              label: 'DIV (Diving)',
              value: _diving,
              onChanged: (v) => setState(() => _diving = v),
            ),
            _AttributeSlider(
              label: 'HAN (Handling)',
              value: _handling,
              onChanged: (v) => setState(() => _handling = v),
            ),
            _AttributeSlider(
              label: 'KIC (Kicking)',
              value: _kicking,
              onChanged: (v) => setState(() => _kicking = v),
            ),
            _AttributeSlider(
              label: 'REF (Reflexes)',
              value: _reflexes,
              onChanged: (v) => setState(() => _reflexes = v),
            ),
            _AttributeSlider(
              label: 'SPD (Speed)',
              value: _speed,
              onChanged: (v) => setState(() => _speed = v),
            ),
            _AttributeSlider(
              label: 'POS (Positioning)',
              value: _positioning,
              onChanged: (v) => setState(() => _positioning = v),
            ),
          ] else ...[
            _AttributeSlider(
              label: 'PAC (Pace)',
              value: _pace,
              onChanged: (v) => setState(() => _pace = v),
            ),
            _AttributeSlider(
              label: 'SHO (Shooting)',
              value: _shooting,
              onChanged: (v) => setState(() => _shooting = v),
            ),
            _AttributeSlider(
              label: 'PAS (Passing)',
              value: _passing,
              onChanged: (v) => setState(() => _passing = v),
            ),
            _AttributeSlider(
              label: 'DRI (Dribbling)',
              value: _dribbling,
              onChanged: (v) => setState(() => _dribbling = v),
            ),
            _AttributeSlider(
              label: 'DEF (Defending)',
              value: _defending,
              onChanged: (v) => setState(() => _defending = v),
            ),
            _AttributeSlider(
              label: 'PHY (Physicality)',
              value: _physical,
              onChanged: (v) => setState(() => _physical = v),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Coach Evaluation',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText:
                  'Provide qualitative notes on technical growth, '
                  'tactical awareness, and mentality...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: isSaving ? null : _save,
            icon: isSaving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: Text(isSaving ? 'Saving…' : 'Save & Sync'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    ).animateScreenEntrance();
  }
}

/// The player's photo, or their initial when no photo is set.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.player, required this.radius});

  final Player player;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = player.photoUrl;
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(radius: radius, backgroundImage: NetworkImage(url));
    }
    return CircleAvatar(
      radius: radius,
      child: Text(
        player.name.isNotEmpty ? player.name[0].toUpperCase() : '?',
        style: TextStyle(fontSize: radius * 0.8),
      ),
    );
  }
}

/// Photo + overall badge, name, position and status chips.
class _PlayerHeader extends StatelessWidget {
  const _PlayerHeader({required this.player, required this.overall});

  final Player player;
  final int overall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            _Avatar(player: player, radius: 40),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.surface, width: 2),
              ),
              child: Text(
                '$overall',
                style: TextStyle(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          player.name,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${player.position?.code ?? 'No position'} · ${player.ageTier.label}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: [
            Chip(
              label: Text(player.eligibility.label),
              visualDensity: VisualDensity.compact,
            ),
            Chip(
              label: Text(player.classYear),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ],
    );
  }
}

/// One attribute row: a label, the current value badge, and a 0–99 slider.
class _AttributeSlider extends StatelessWidget {
  const _AttributeSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$value',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            Slider(
              value: value.toDouble(),
              min: 0,
              max: 99,
              divisions: 99,
              label: '$value',
              onChanged: (v) => onChanged(v.round()),
            ),
          ],
        ),
      ),
    );
  }
}
