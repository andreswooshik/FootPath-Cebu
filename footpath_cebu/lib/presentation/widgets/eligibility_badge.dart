import 'package:flutter/material.dart';

import 'package:footpath_cebu/domain/entities/player.dart';

/// A colour-coded chip for a single [EligibilityStatus] value.
class EligibilityBadge extends StatelessWidget {
  const EligibilityBadge({
    super.key,
    required this.status,
    this.applicable = true,
  });

  final EligibilityStatus status;
  final bool applicable;

  @override
  Widget build(BuildContext context) {
    final color = !applicable
        ? Colors.grey
        : switch (status) {
            EligibilityStatus.eligible => Colors.green,
            EligibilityStatus.notEligible => Colors.red,
            EligibilityStatus.pending => Colors.orange,
            EligibilityStatus.academicWarning => Colors.amber.shade800,
          };

    return Chip(
      label: Text(applicable ? status.label : 'Eligibility N/A'),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color),
      visualDensity: VisualDensity.compact,
    );
  }
}
