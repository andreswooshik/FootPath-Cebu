import 'package:flutter/material.dart';

import 'package:footpath_cebu/domain/entities/card_tier.dart';

/// A collectible-card tier pill (Bronze / Silver / Gold) with a medal icon and
/// a metallic-tinted background, sized for headers and card rows.
class TierBadge extends StatelessWidget {
  const TierBadge({super.key, required this.tier, this.compact = false});

  final CardTier tier;

  /// Drops the label, leaving just the medal — for tight spaces.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = Color(tier.argb);
    final onColor = ThemeData.estimateBrightnessForColor(color) ==
            Brightness.dark
        ? Colors.white
        : const Color(0xFF3A2A0A);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.95), color.withValues(alpha: 0.7)],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium, size: 16, color: onColor),
          if (!compact) ...[
            const SizedBox(width: 5),
            Text(
              '${tier.label} Card',
              style: TextStyle(
                color: onColor,
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
