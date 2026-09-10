import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/domain/entities/attendance_sync_entry.dart';
import 'package:footpath_cebu/presentation/providers/attendance_sync_providers.dart';
import 'package:footpath_cebu/presentation/screens/attendance_sync_screen.dart';

class AttendanceSyncButton extends ConsumerWidget {
  const AttendanceSyncButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(attendanceSyncEntriesProvider);
    final count = entries.asData?.value.length ?? 0;
    return IconButton(
      tooltip: 'Attendance sync',
      icon: Badge(
        label: Text(entries.hasError ? '!' : '$count'),
        isLabelVisible: count > 0 || entries.hasError,
        child: const Icon(Icons.cloud_upload_outlined),
      ),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AttendanceSyncScreen()),
      ),
    );
  }
}

class AttendanceSyncStatus extends ConsumerWidget {
  const AttendanceSyncStatus({super.key, required this.sessionId});
  final String sessionId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries =
        ref.watch(attendanceSyncEntriesProvider).asData?.value ?? [];
    AttendanceSyncEntry? entry;
    for (final value in entries) {
      if (value.sessionId == sessionId) entry = value;
    }
    if (entry == null) return const SizedBox.shrink();
    return TextButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AttendanceSyncScreen()),
      ),
      icon: Icon(
        entry.status == AttendanceDeliveryStatus.needsCorrection
            ? Icons.error_outline
            : Icons.cloud_upload_outlined,
      ),
      label: Text(
        entry.status == AttendanceDeliveryStatus.needsCorrection
            ? 'Needs correction · Review saved attendance'
            : 'Waiting to sync · Saved on this device',
      ),
    );
  }
}
