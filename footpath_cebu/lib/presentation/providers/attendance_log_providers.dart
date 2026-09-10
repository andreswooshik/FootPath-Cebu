import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/presentation/providers/mutation_controller.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/entities/attendance_sync_entry.dart';
import 'package:footpath_cebu/presentation/providers/training_schedule_providers.dart';

/// The effort a present player is assumed to have given until the coach moves
/// the slider. Mid-range on purpose: it should read as "not yet judged" rather
/// than flatter or punish a player nobody assessed.
const kDefaultEffort = 70;

/// Attendance already saved for one session, keyed by session id. Lets the
/// screen preload the marks a coach made last time instead of a blank roster.
///
/// autoDispose + family: one cache entry per session, dropped when the screen
/// leaves. Refresh with `ref.refresh(sessionAttendanceProvider(id).future)`.
final sessionAttendanceProvider = FutureProvider.autoDispose
    .family<List<Attendance>, String>(
      (ref, sessionId) => ref.watch(getSessionAttendanceProvider)(sessionId),
    );

/// Drives both the first attendance save and later "Update Changes" action.
///
/// Owns only the submit state ([AsyncValue] loading/error), mirroring
/// [ScheduleSessionController]. The per-player marks are transient form state
/// and live in the screen, handed over here as a finished [records] list.
class AttendanceLogController extends MutationController {
  AttendanceDeliveryStatus lastDeliveryStatus =
      AttendanceDeliveryStatus.unknown;

  /// Persists [records] for [sessionId]. Returns true on success so the screen
  /// can pop. Invalidates the schedule (attendee counts change) and this
  /// session's saved attendance (so a re-open reflects what was just saved).
  Future<bool> save(String sessionId, List<Attendance> records) async {
    return await runMutation(
          () async {
            await ref.read(logSessionAttendanceProvider)(sessionId, records);
            if (!ref.mounted) return false;
            // A status lookup failure must not turn a durable save into a
            // reported failure or incorrectly claim server confirmation.
            lastDeliveryStatus = AttendanceDeliveryStatus.unknown;
            try {
              final entries = await ref
                  .read(attendanceSyncRepositoryProvider)
                  .fetchEntries();
              lastDeliveryStatus = AttendanceDeliveryStatus.savedOnServer;
              for (final entry in entries) {
                if (entry.sessionId == sessionId) {
                  lastDeliveryStatus = entry.status;
                }
              }
            } catch (_) {}
            return true;
          },
          onSuccess: (result) {
            ref.invalidate(sessionAttendanceProvider(sessionId));
            ref.invalidate(trainingSessionsProvider);
          },
        ) ??
        false;
  }
}

final attendanceLogControllerProvider =
    AsyncNotifierProvider.autoDispose<AttendanceLogController, void>(
      AttendanceLogController.new,
    );
