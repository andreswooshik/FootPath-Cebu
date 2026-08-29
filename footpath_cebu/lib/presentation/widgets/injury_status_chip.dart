import 'package:flutter/material.dart';

import 'package:footpath_cebu/domain/entities/injury_record.dart';
import 'package:footpath_cebu/presentation/widgets/app_status_chip.dart';

/// A colour-coded chip for a single [InjuryStatus] value.
class InjuryStatusChip extends StatelessWidget {
  const InjuryStatusChip({super.key, required this.status});

  final InjuryStatus status;

  @override
  Widget build(BuildContext context) {
    final (tone, icon) = switch (status) {
      InjuryStatus.active => (AppStatusTone.danger, Icons.error_outline),
      InjuryStatus.recovering => (
        AppStatusTone.warning,
        Icons.healing_outlined,
      ),
      InjuryStatus.recovered => (
        AppStatusTone.success,
        Icons.check_circle_outline,
      ),
    };
    return AppStatusChip(label: status.label, tone: tone, icon: icon);
  }
}
