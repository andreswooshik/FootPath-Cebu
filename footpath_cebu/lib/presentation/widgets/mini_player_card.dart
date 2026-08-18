import 'package:flutter/material.dart';

import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/card_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';

/// A minimized "Ultimate Team" card for the roster list: a tier-tinted strip
/// with the overall rating, the player's photo, name, position and academic
/// dot, and a quick-action affordance. Denser than the full [PlayerCard] so a
/// coach can scan the whole squad at once.
class MiniPlayerCard extends StatelessWidget {
  const MiniPlayerCard({
    super.key,
    required this.player,
    this.onTap,
    this.onMarkAttendance,
  });

  final Player player;
  final VoidCallback? onTap;
  final VoidCallback? onMarkAttendance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tier = CardTier.forPlayer(player);
    final tierColor = Color(tier.argb);

    return MotionPress(
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                // Overall + tier medallion.
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        tierColor,
                        Color.lerp(tierColor, Colors.black, 0.25)!,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${player.overall}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          height: 1,
                        ),
                      ),
                      Text(
                        player.position?.code ?? '--',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        player.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: player.academicEligibilityApplicable
                                  ? _eligibilityColor(player.eligibility)
                                  : Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${player.ageTier.label} · ${tier.label}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onMarkAttendance != null)
                  IconButton(
                    tooltip: 'Mark attendance',
                    icon: const Icon(Icons.how_to_reg_outlined),
                    color: theme.colorScheme.primary,
                    onPressed: onMarkAttendance,
                  ),
                Icon(Icons.chevron_right, color: theme.colorScheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Semantic status scale shared with the other eligibility indicators
// (player/guardian dashboards, profile) — kept separate from the teal/coral
// brand palette so a status dot never reads as brand chrome.
Color _eligibilityColor(EligibilityStatus status) => switch (status) {
  EligibilityStatus.eligible => Colors.green,
  EligibilityStatus.notEligible => Colors.red,
  EligibilityStatus.pending => Colors.orange,
  EligibilityStatus.academicWarning => Colors.amber.shade800,
};
