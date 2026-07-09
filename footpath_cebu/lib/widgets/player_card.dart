import 'package:flutter/material.dart';

import '../models/player.dart';

/// A FUT-style squad card: the green rating card on top, with the player's
/// real name, age/class, and academic-standing badge underneath.
class PlayerCard extends StatelessWidget {
  const PlayerCard({super.key, required this.player, this.onTap});

  final Player player;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _RatingCard(player: player),
              const SizedBox(height: 12),
              Text(
                player.name,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                '${player.age} Years Old • ${player.classYear}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Text(
                'ACADEMIC STANDING',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 0.5,
                      color: Colors.grey.shade600,
                    ),
              ),
              const SizedBox(height: 4),
              _EligibilityBadge(status: player.eligibility),
            ],
          ),
        ),
      ),
    );
  }
}

/// The green FIFA-Ultimate-Team style card face.
class _RatingCard extends StatelessWidget {
  const _RatingCard({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    final r = player.ratings;
    return Container(
      width: 220,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32), Color(0xFF43A047)],
        ),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '${player.overall}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  Text(
                    player.position,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const Icon(Icons.person, color: Colors.white70, size: 56),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 10),
          _StatRow(stats: [
            ('PAC', r.pace),
            ('SHO', r.shooting),
            ('PAS', r.passing),
          ]),
          const SizedBox(height: 8),
          _StatRow(stats: [
            ('DRI', r.dribbling),
            ('DEF', r.defending),
            ('PHY', r.physical),
          ]),
        ],
      ),
    );
  }
}

/// A row of three attribute chips that share the width evenly and scale down
/// rather than overflow on narrow layouts.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.stats});

  final List<(String, int)> stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (label, value) in stats)
          Expanded(child: _Stat(label: label, value: value)),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _EligibilityBadge extends StatelessWidget {
  const _EligibilityBadge({required this.status});

  final EligibilityStatus status;

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final IconData icon;
    switch (status) {
      case EligibilityStatus.eligible:
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case EligibilityStatus.academicWarning:
        color = Colors.orange;
        icon = Icons.warning_amber_rounded;
        break;
      case EligibilityStatus.notEligible:
        color = Colors.red;
        icon = Icons.cancel;
        break;
      case EligibilityStatus.pending:
        color = Colors.blueGrey;
        icon = Icons.hourglass_bottom;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
