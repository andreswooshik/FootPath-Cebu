import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';

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

/// Drives the "Complete Training Session" action.
///
/// Owns only the submit state ([AsyncValue] loading/error), mirroring
/// [ScheduleSessionController]. The per-player marks are transient form state
/// and live in the screen, handed over here as a finished [records] list.
class AttendanceLogController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Persists [records] for [sessionId]. Returns true on success so the screen
  /// can pop. Invalidates the schedule (attendee counts change) and this
  /// session's saved attendance (so a re-open reflects what was just saved).
  Future<bool> save(String sessionId, List<Attendance> records) async {
    state = const AsyncLoading();
    try {
      await ref.read(logSessionAttendanceProvider)(sessionId, records);
      state = const AsyncData(null);
      ref.invalidate(sessionAttendanceProvider(sessionId));
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}

final attendanceLogControllerProvider =
    AsyncNotifierProvider.autoDispose<AttendanceLogController, void>(
      AttendanceLogController.new,
    );
