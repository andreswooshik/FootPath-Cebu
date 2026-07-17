import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/data/repositories/api_attendance_repository.dart';
import 'package:footpath_cebu/data/repositories/api_device_repository.dart';
import 'package:footpath_cebu/data/repositories/api_player_repository.dart';
import 'package:footpath_cebu/data/repositories/api_training_repository.dart';
import 'package:footpath_cebu/data/repositories/firebase_auth_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_attendance_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_auth_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_device_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_player_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_training_repository.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';
import 'package:footpath_cebu/domain/repositories/auth_repository.dart';
import 'package:footpath_cebu/domain/repositories/device_repository.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';
import 'package:footpath_cebu/domain/repositories/training_repository.dart';
import 'package:footpath_cebu/domain/usecases/get_linked_players.dart';
import 'package:footpath_cebu/domain/usecases/get_my_profile.dart';
import 'package:footpath_cebu/domain/usecases/get_player_attendance.dart';
import 'package:footpath_cebu/domain/usecases/get_session_attendance.dart';
import 'package:footpath_cebu/domain/usecases/get_squad.dart';
import 'package:footpath_cebu/domain/usecases/get_training_sessions.dart';
import 'package:footpath_cebu/domain/usecases/log_session_attendance.dart';
import 'package:footpath_cebu/domain/usecases/register_device.dart';
import 'package:footpath_cebu/domain/usecases/save_player_assessment.dart';
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

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => useMockData ? MockAttendanceRepository() : ApiAttendanceRepository(),
);

final trainingRepositoryProvider = Provider<TrainingRepository>(
  (ref) => useMockData ? MockTrainingRepository() : ApiTrainingRepository(),
);

final deviceRepositoryProvider = Provider<DeviceRepository>(
  // The live repository takes an optional PushTokenProvider; pass one here
  // once a compatible firebase_messaging is pinned (see
  // docs/wiring-implementation-notes.md).
  (ref) => useMockData ? MockDeviceRepository() : ApiDeviceRepository(),
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

final getPlayerAttendanceProvider = Provider<GetPlayerAttendance>(
  (ref) => GetPlayerAttendance(ref.watch(attendanceRepositoryProvider)),
);

final getSessionAttendanceProvider = Provider<GetSessionAttendance>(
  (ref) => GetSessionAttendance(ref.watch(attendanceRepositoryProvider)),
);

final logSessionAttendanceProvider = Provider<LogSessionAttendance>(
  (ref) => LogSessionAttendance(ref.watch(attendanceRepositoryProvider)),
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
