import 'package:flutter/material.dart';

import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';

/// Compact roster card with the player's development-assessment status.
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
    final assessment = player.developmentAssessment;

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
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.primaryContainer,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    assessment == null
                        ? Icons.hourglass_empty_outlined
                        : Icons.insights_outlined,
                    color: theme.colorScheme.onPrimary,
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
                          if (player.academicEligibilityApplicable) ...[
                            Container(
                              key: const Key('mini-player-eligibility'),
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _eligibilityColor(player.eligibility),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              '${player.ageTier.label} · ${player.position?.code ?? 'Unassigned'} · ${assessment == null ? 'Awaiting assessment' : '5 domains assessed'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
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
