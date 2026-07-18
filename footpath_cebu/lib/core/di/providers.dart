import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/data/local/attendance_outbox.dart';
import 'package:footpath_cebu/data/local/attendance_sync_service.dart';
import 'package:footpath_cebu/data/repositories/api_attendance_repository.dart';
import 'package:footpath_cebu/data/repositories/api_device_repository.dart';
import 'package:footpath_cebu/data/repositories/api_dispute_repository.dart';
import 'package:footpath_cebu/data/repositories/api_injury_repository.dart';
import 'package:footpath_cebu/data/repositories/api_player_repository.dart';
import 'package:footpath_cebu/data/repositories/api_session_confirmation_repository.dart';
import 'package:footpath_cebu/data/repositories/api_training_repository.dart';
import 'package:footpath_cebu/data/repositories/firebase_auth_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_attendance_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_auth_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_device_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_dispute_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_injury_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_player_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_session_confirmation_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_training_repository.dart';
import 'package:footpath_cebu/data/repositories/offline_first_attendance_repository.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';
import 'package:footpath_cebu/domain/repositories/auth_repository.dart';
import 'package:footpath_cebu/domain/repositories/device_repository.dart';
import 'package:footpath_cebu/domain/repositories/dispute_repository.dart';
import 'package:footpath_cebu/domain/repositories/injury_repository.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';
import 'package:footpath_cebu/domain/repositories/session_confirmation_repository.dart';
import 'package:footpath_cebu/domain/repositories/training_repository.dart';
import 'package:footpath_cebu/domain/usecases/confirm_session.dart';
import 'package:footpath_cebu/domain/usecases/delete_injury.dart';
import 'package:footpath_cebu/domain/usecases/get_disputes.dart';
import 'package:footpath_cebu/domain/usecases/get_injuries.dart';
import 'package:footpath_cebu/domain/usecases/get_linked_players.dart';
import 'package:footpath_cebu/domain/usecases/get_my_profile.dart';
import 'package:footpath_cebu/domain/usecases/get_player_attendance.dart';
import 'package:footpath_cebu/domain/usecases/get_session_attendance.dart';
import 'package:footpath_cebu/domain/usecases/get_session_confirmations.dart';
import 'package:footpath_cebu/domain/usecases/get_squad.dart';
import 'package:footpath_cebu/domain/usecases/get_training_sessions.dart';
import 'package:footpath_cebu/domain/usecases/log_session_attendance.dart';
import 'package:footpath_cebu/domain/usecases/raise_dispute.dart';
import 'package:footpath_cebu/domain/usecases/register_device.dart';
import 'package:footpath_cebu/domain/usecases/respond_to_dispute.dart';
import 'package:footpath_cebu/domain/usecases/save_injury.dart';
import 'package:footpath_cebu/domain/usecases/save_player_assessment.dart';
import 'package:footpath_cebu/domain/usecases/save_player_position.dart';
import 'package:footpath_cebu/domain/usecases/schedule_training_session.dart';
import 'package:footpath_cebu/domain/usecases/send_password_reset.dart';
import 'package:footpath_cebu/domain/usecases/sign_in.dart';
import 'package:footpath_cebu/domain/usecases/sign_out.dart';

/// Composition root (the outermost layer), expressed as Riverpod providers.
///
/// The repository providers pick the concrete data-layer implementation
/// (mock vs live); the use-case providers wire the domain layer the
/// presentation providers depend on. Swapping mock <-> live happens here and
/// nowhere else. Tests override the repository providers with fakes via
/// `ProviderScope(overrides: ...)` / `ProviderContainer(overrides: ...)`.

/// Whether to wire the in-memory mock repositories instead of the live
/// Firebase + Django backend.
///
/// A release build ALWAYS uses live data — the mock auth accepts a shared demo
/// password for any email, so it must never ship (audit finding F1). In debug,
/// mocks are the default for UI work; override with
/// `--dart-define=USE_MOCK=false` to run debug against the real backend.
bool get useMockData {
  if (kReleaseMode) return false;
  return const bool.fromEnvironment('USE_MOCK', defaultValue: true);
}

// ---------------------------------------------------------------------------
// Data layer — one provider per repository interface.
// ---------------------------------------------------------------------------

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => useMockData ? MockAuthRepository() : FirebaseAuthRepository(),
);

final playerRepositoryProvider = Provider<PlayerRepository>(
  (ref) => useMockData ? MockPlayerRepository() : ApiPlayerRepository(),
);

/// Durable outbox for attendance saves made while offline. One app-wide
/// instance so the repository decorator and the sync service drain the same
/// queue.
final attendanceOutboxProvider = Provider<AttendanceOutbox>((ref) {
  final outbox = AttendanceOutbox();
  ref.onDispose(outbox.close);
  return outbox;
});

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => useMockData
      ? MockAttendanceRepository()
      // Live attendance is offline-first: writes that fail at the network
      // level are queued in the outbox and replayed by the sync service.
      : OfflineFirstAttendanceRepository(
          inner: ApiAttendanceRepository(),
          outbox: ref.watch(attendanceOutboxProvider),
        ),
);

/// Drains the offline outbox when connectivity returns. Null in mock mode
/// (nothing real to sync). Started once post-login, alongside
/// [registerDeviceProvider].
final attendanceSyncServiceProvider = Provider<AttendanceSyncService?>((ref) {
  if (useMockData) return null;
  final service = AttendanceSyncService(
    outbox: ref.watch(attendanceOutboxProvider),
    inner: ApiAttendanceRepository(),
  );
  ref.onDispose(service.dispose);
  return service;
});

final trainingRepositoryProvider = Provider<TrainingRepository>(
  (ref) => useMockData ? MockTrainingRepository() : ApiTrainingRepository(),
);

final injuryRepositoryProvider = Provider<InjuryRepository>(
  (ref) => useMockData ? MockInjuryRepository() : ApiInjuryRepository(),
);

final disputeRepositoryProvider = Provider<DisputeRepository>(
  (ref) => useMockData ? MockDisputeRepository() : ApiDisputeRepository(),
);

/// Player RSVPs now persist through the Django API (survive logout/restart and
/// are visible to the coach); the in-memory mock stays the default for UI work.
final sessionConfirmationRepositoryProvider =
    Provider<SessionConfirmationRepository>(
  (ref) => useMockData
      ? MockSessionConfirmationRepository()
      : ApiSessionConfirmationRepository(),
);

final deviceRepositoryProvider = Provider<DeviceRepository>(
  // The FCM plugin dependency lives here (the composition root), not in the
  // repository — exactly the seam ApiDeviceRepository documents. Failures are
  // swallowed inside registerCurrentDevice; push must never break login.
  (ref) => useMockData
      ? MockDeviceRepository()
      : ApiDeviceRepository(() async {
          await FirebaseMessaging.instance.requestPermission();
          return FirebaseMessaging.instance.getToken();
        }),
);

// ---------------------------------------------------------------------------
// Domain layer — one provider per use case.
// ---------------------------------------------------------------------------

final signInProvider = Provider<SignIn>(
  (ref) => SignIn(ref.watch(authRepositoryProvider)),
);

final signOutProvider = Provider<SignOut>(
  (ref) => SignOut(ref.watch(authRepositoryProvider)),
);

final sendPasswordResetProvider = Provider<SendPasswordReset>(
  (ref) => SendPasswordReset(ref.watch(authRepositoryProvider)),
);

final getSquadProvider = Provider<GetSquad>(
  (ref) => GetSquad(ref.watch(playerRepositoryProvider)),
);

final getMyProfileProvider = Provider<GetMyProfile>(
  (ref) => GetMyProfile(ref.watch(playerRepositoryProvider)),
);

final getLinkedPlayersProvider = Provider<GetLinkedPlayers>(
  (ref) => GetLinkedPlayers(ref.watch(playerRepositoryProvider)),
);

final savePlayerAssessmentProvider = Provider<SavePlayerAssessment>(
  (ref) => SavePlayerAssessment(ref.watch(playerRepositoryProvider)),
);

final savePlayerPositionProvider = Provider<SavePlayerPosition>(
  (ref) => SavePlayerPosition(ref.watch(playerRepositoryProvider)),
);

final getPlayerAttendanceProvider = Provider<GetPlayerAttendance>(
  (ref) => GetPlayerAttendance(ref.watch(attendanceRepositoryProvider)),
);

final getSessionAttendanceProvider = Provider<GetSessionAttendance>(
  (ref) => GetSessionAttendance(ref.watch(attendanceRepositoryProvider)),
);

final logSessionAttendanceProvider = Provider<LogSessionAttendance>(
  (ref) => LogSessionAttendance(ref.watch(attendanceRepositoryProvider)),
);

final getInjuriesProvider = Provider<GetInjuries>(
  (ref) => GetInjuries(ref.watch(injuryRepositoryProvider)),
);

final saveInjuryProvider = Provider<SaveInjury>(
  (ref) => SaveInjury(ref.watch(injuryRepositoryProvider)),
);

final deleteInjuryProvider = Provider<DeleteInjury>(
  (ref) => DeleteInjury(ref.watch(injuryRepositoryProvider)),
);

final getDisputesProvider = Provider<GetDisputes>(
  (ref) => GetDisputes(ref.watch(disputeRepositoryProvider)),
);

final raiseDisputeProvider = Provider<RaiseDispute>(
  (ref) => RaiseDispute(ref.watch(disputeRepositoryProvider)),
);

final respondToDisputeProvider = Provider<RespondToDispute>(
  (ref) => RespondToDispute(ref.watch(disputeRepositoryProvider)),
);

final getSessionConfirmationsProvider = Provider<GetSessionConfirmations>(
  (ref) => GetSessionConfirmations(
    ref.watch(sessionConfirmationRepositoryProvider),
  ),
);

final confirmSessionProvider = Provider<ConfirmSession>(
  (ref) => ConfirmSession(ref.watch(sessionConfirmationRepositoryProvider)),
);

final getTrainingSessionsProvider = Provider<GetTrainingSessions>(
  (ref) => GetTrainingSessions(ref.watch(trainingRepositoryProvider)),
);

final scheduleTrainingSessionProvider = Provider<ScheduleTrainingSession>(
  (ref) => ScheduleTrainingSession(ref.watch(trainingRepositoryProvider)),
);

final registerDeviceProvider = Provider<RegisterDevice>(
  (ref) => RegisterDevice(ref.watch(deviceRepositoryProvider)),
);
