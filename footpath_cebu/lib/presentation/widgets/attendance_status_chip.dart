import 'package:flutter/material.dart';

import 'package:footpath_cebu/domain/entities/attendance.dart';

/// A colour-coded chip for a single [AttendanceStatus] value.
class AttendanceStatusChip extends StatelessWidget {
  const AttendanceStatusChip({super.key, required this.status});

  final AttendanceStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      AttendanceStatus.present => (Colors.green, Icons.check_circle_outline),
      AttendanceStatus.absent => (Colors.red, Icons.cancel_outlined),
      AttendanceStatus.excused => (Colors.blueGrey, Icons.info_outline),
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
