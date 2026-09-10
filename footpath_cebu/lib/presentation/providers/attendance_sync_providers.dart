import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/attendance_sync_entry.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/presentation/providers/mutation_controller.dart';
import 'package:footpath_cebu/presentation/providers/attendance_log_providers.dart';
import 'package:footpath_cebu/presentation/providers/training_schedule_providers.dart';

final attendanceSyncEntriesProvider =
    StreamProvider.autoDispose<List<AttendanceSyncEntry>>(
      (ref) => ref.watch(attendanceSyncRepositoryProvider).watchEntries(),
    );

class AttendanceSyncController extends MutationController {
  Future<bool> saveCorrection(
    AttendanceSyncEntry entry,
    List<Attendance> records,
  ) async =>
      await runMutation(
        () async {
          await ref
              .read(attendanceSyncRepositoryProvider)
              .saveCorrection(entry, records);
          return true;
        },
        onSuccess: (_) {
          ref.invalidate(sessionAttendanceProvider(entry.sessionId));
          ref.invalidate(trainingSessionsProvider);
        },
      ) ??
      false;
  Future<void> syncNow() async {
    await runMutation(() async {
      await ref.read(attendanceSyncRepositoryProvider).syncNow();
      return true;
    });
  }
}

final attendanceSyncControllerProvider =
    AsyncNotifierProvider.autoDispose<AttendanceSyncController, void>(
      AttendanceSyncController.new,
    );
