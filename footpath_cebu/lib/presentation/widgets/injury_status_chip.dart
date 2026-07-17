import 'package:flutter/material.dart';

import 'package:footpath_cebu/domain/entities/injury_record.dart';

/// A colour-coded chip for a single [InjuryStatus] value.
class InjuryStatusChip extends StatelessWidget {
  const InjuryStatusChip({super.key, required this.status});

  final InjuryStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      InjuryStatus.active => (Colors.red, Icons.error_outline),
      InjuryStatus.recovering => (Colors.orange, Icons.healing_outlined),
      InjuryStatus.recovered => (Colors.green, Icons.check_circle_outline),
    };

    return Chip(
      avatar: Icon(icon, color: color, size: 18),
      label: Text(status.label),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color),
      visualDensity: VisualDensity.compact,
    );
  }
}
