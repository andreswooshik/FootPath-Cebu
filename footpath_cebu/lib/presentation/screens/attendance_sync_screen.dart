import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/domain/entities/attendance_sync_entry.dart';
import 'package:footpath_cebu/presentation/providers/attendance_sync_providers.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/screens/attendance_recovery_screen.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';

class AttendanceSyncScreen extends ConsumerWidget {
  const AttendanceSyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(attendanceSyncEntriesProvider);
    final action = ref.watch(attendanceSyncControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance sync')),
      body: entries.when(
        loading: () => const DashboardLoadingState(),
        error: (error, _) => DashboardErrorState(
          message: friendlyErrorMessage(
            error,
            'Could not read saved attendance on this device.',
          ),
          onRetry: () => ref.invalidate(attendanceSyncEntriesProvider),
        ),
        data: (rows) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Attendance saved on this device stays here until the server accepts it. Corrections are checked against the current session rules.',
            ),
            const SizedBox(height: 12),
            if (action.hasError)
              Text(
                friendlyErrorMessage(
                  action.error,
                  'Could not sync attendance. Please try again.',
                ),
              ),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text('No attendance waiting to sync on this device.'),
              ),
            if (rows.any(
              (row) => row.status == AttendanceDeliveryStatus.waitingToSync,
            ))
              FilledButton.icon(
                onPressed: action.isLoading
                    ? null
                    : () => ref
                          .read(attendanceSyncControllerProvider.notifier)
                          .syncNow(),
                icon: const Icon(Icons.sync),
                label: Text(action.isLoading ? 'Syncing…' : 'Sync now'),
              ),
            for (final entry in rows)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.sessionName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        entry.status == AttendanceDeliveryStatus.needsCorrection
                            ? 'Needs correction'
                            : 'Waiting to sync',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${entry.records.length} attendance records retained',
                      ),
                      if (entry.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(entry.error!),
                        ),
                      if (entry.status ==
                          AttendanceDeliveryStatus.needsCorrection)
                        const Text(
                          'Automatic retries are paused. Review the reason above, correct the marks, and save again. If the session is closed or missing, ask your coordinator to resolve it; your records remain here.',
                        ),
                      TextButton(
                        onPressed: action.isLoading
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      AttendanceRecoveryScreen(entry: entry),
                                ),
                              ),
                        child: const Text('Review saved marks'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
