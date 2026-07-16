import 'package:flutter/material.dart';

import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/screens/edit_performance_data_screen.dart';
import 'package:footpath_cebu/presentation/widgets/coach_bottom_nav.dart';
import 'package:footpath_cebu/presentation/widgets/player_card.dart';

/// Coach Portal — one player's profile, opened by tapping a card on the squad
/// roster. Shows the FUT card, the six technical attributes, and the player's
/// academic standing, and links to the assessment form.
///
/// Holds the player locally so ratings edited in [EditPerformanceDataScreen]
/// are reflected on the card as soon as the coach saves.
class PlayerProfileScreen extends StatefulWidget {
  const PlayerProfileScreen({
    super.key,
    required this.player,
    required this.profile,
  });

  final Player player;

  /// The signed-in coach, forwarded to the shared bottom navigation.
  final UserProfile profile;

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
  late Player _player = widget.player;

  Future<void> _openEditor() async {
    final updated = await Navigator.of(context).push<PlayerRatings>(
      MaterialPageRoute(
        builder: (_) => EditPerformanceDataScreen(
          player: _player,
          profile: widget.profile,
        ),
      ),
    );
    if (updated == null) return;
    setState(() => _player = _player.copyWith(ratings: updated));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _player.ratings;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Player Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Coming soon.')),
            ),
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
            children: [
              _AttributeTile(label: 'PAC', value: r.pace),
              _AttributeTile(label: 'SHO', value: r.shooting),
              _AttributeTile(label: 'PAS', value: r.passing),
              _AttributeTile(label: 'DRI', value: r.dribbling),
              _AttributeTile(label: 'DEF', value: r.defending),
              _AttributeTile(label: 'PHY', value: r.physical),
            ],
          ),
          const SizedBox(height: 16),
          _AcademicStandingCard(status: _player.eligibility),
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
      bottomNavigationBar: CoachBottomNav(profile: widget.profile),
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
            child: const Icon(Icons.school_outlined,
                color: Colors.white, size: 18),
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
