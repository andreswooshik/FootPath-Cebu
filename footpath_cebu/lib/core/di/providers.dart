import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/data/local/attendance_outbox.dart';
import 'package:footpath_cebu/data/local/attendance_sync_service.dart';
import 'package:footpath_cebu/data/repositories/api_age_tier_repository.dart';
import 'package:footpath_cebu/data/repositories/api_attendance_repository.dart';
import 'package:footpath_cebu/data/repositories/api_device_repository.dart';
import 'package:footpath_cebu/data/repositories/api_dispute_repository.dart';
import 'package:footpath_cebu/data/repositories/api_eligibility_history_repository.dart';
import 'package:footpath_cebu/data/repositories/api_injury_repository.dart';
import 'package:footpath_cebu/data/repositories/api_growth_repository.dart';
import 'package:footpath_cebu/data/repositories/api_match_repository.dart';
import 'package:footpath_cebu/data/repositories/api_notification_repository.dart';
import 'package:footpath_cebu/data/repositories/api_player_repository.dart';
import 'package:footpath_cebu/data/repositories/api_player_stats_repository.dart';
import 'package:footpath_cebu/data/repositories/api_player_privacy_pin_repository.dart';
import 'package:footpath_cebu/data/repositories/api_progress_repository.dart';
import 'package:footpath_cebu/data/repositories/api_profile_photo_repository.dart';
import 'package:footpath_cebu/data/repositories/api_session_confirmation_repository.dart';
import 'package:footpath_cebu/data/repositories/api_training_repository.dart';
import 'package:footpath_cebu/data/repositories/api_tournament_schedule_repository.dart';
import 'package:footpath_cebu/data/repositories/api_tournament_roster_repository.dart';
import 'package:footpath_cebu/data/repositories/firebase_auth_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_age_tier_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_attendance_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_auth_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_device_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_dispute_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_eligibility_history_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_injury_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_growth_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_match_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_notification_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_player_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_player_privacy_pin_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_progress_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_profile_photo_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_session_confirmation_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_training_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_tournament_schedule_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_tournament_roster_repository.dart';
import 'package:footpath_cebu/data/repositories/offline_first_attendance_repository.dart';
import 'package:footpath_cebu/core/security/player_unlock_token_store.dart';
import 'package:footpath_cebu/domain/repositories/age_tier_repository.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';
import 'package:footpath_cebu/domain/repositories/auth_repository.dart';
import 'package:footpath_cebu/domain/repositories/device_repository.dart';
import 'package:footpath_cebu/domain/repositories/development_assessment_repository.dart';
import 'package:footpath_cebu/domain/repositories/dispute_repository.dart';
import 'package:footpath_cebu/domain/repositories/eligibility_history_repository.dart';
import 'package:footpath_cebu/domain/repositories/injury_repository.dart';
import 'package:footpath_cebu/domain/repositories/growth_repository.dart';
import 'package:footpath_cebu/domain/repositories/match_repository.dart';
import 'package:footpath_cebu/domain/repositories/notification_repository.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';
import 'package:footpath_cebu/domain/repositories/player_stats_repository.dart';
import 'package:footpath_cebu/domain/repositories/player_privacy_pin_repository.dart';
import 'package:footpath_cebu/domain/repositories/progress_repository.dart';
import 'package:footpath_cebu/domain/repositories/profile_photo_repository.dart';
import 'package:footpath_cebu/domain/repositories/session_confirmation_repository.dart';
import 'package:footpath_cebu/domain/repositories/training_repository.dart';
import 'package:footpath_cebu/domain/repositories/tournament_schedule_repository.dart';
import 'package:footpath_cebu/domain/repositories/tournament_roster_repository.dart';
import 'package:footpath_cebu/domain/usecases/confirm_session.dart';
import 'package:footpath_cebu/domain/usecases/create_football_match.dart';
import 'package:footpath_cebu/domain/usecases/delete_match_performance.dart';
import 'package:footpath_cebu/domain/usecases/delete_match_rating.dart';
import 'package:footpath_cebu/domain/usecases/development_assessment.dart';
import 'package:footpath_cebu/domain/usecases/get_age_tier_bands.dart';
import 'package:footpath_cebu/domain/usecases/delete_injury.dart';
import 'package:footpath_cebu/domain/usecases/get_disputes.dart';
import 'package:footpath_cebu/domain/usecases/get_eligibility_history.dart';
import 'package:footpath_cebu/domain/usecases/get_injuries.dart';
import 'package:footpath_cebu/domain/usecases/get_linked_players.dart';
import 'package:footpath_cebu/domain/usecases/get_football_matches.dart';
import 'package:footpath_cebu/domain/usecases/get_match_performances.dart';
import 'package:footpath_cebu/domain/usecases/get_match_roster.dart';
import 'package:footpath_cebu/domain/usecases/get_my_profile.dart';
import 'package:footpath_cebu/domain/usecases/get_player_details.dart';
import 'package:footpath_cebu/domain/usecases/get_player_attendance.dart';
import 'package:footpath_cebu/domain/usecases/get_player_privacy_pin_status.dart';
import 'package:footpath_cebu/domain/usecases/get_player_match_statistics.dart';
import 'package:footpath_cebu/domain/usecases/get_session_attendance.dart';
import 'package:footpath_cebu/domain/usecases/get_session_confirmations.dart';
import 'package:footpath_cebu/domain/usecases/get_squad.dart';
import 'package:footpath_cebu/domain/usecases/get_squad_progress.dart';
import 'package:footpath_cebu/domain/usecases/get_training_sessions.dart';
import 'package:footpath_cebu/domain/usecases/log_session_attendance.dart';
import 'package:footpath_cebu/domain/usecases/raise_dispute.dart';
import 'package:footpath_cebu/domain/usecases/register_device.dart';
import 'package:footpath_cebu/domain/usecases/restore_session.dart';
import 'package:footpath_cebu/domain/usecases/respond_to_dispute.dart';
import 'package:footpath_cebu/domain/usecases/save_injury.dart';
import 'package:footpath_cebu/domain/usecases/save_match_performance.dart';
import 'package:footpath_cebu/domain/usecases/save_match_rating.dart';
import 'package:footpath_cebu/domain/usecases/save_player_assessment.dart';
import 'package:footpath_cebu/domain/usecases/save_player_position.dart';
import 'package:footpath_cebu/domain/usecases/set_player_privacy_pin.dart';
import 'package:footpath_cebu/domain/usecases/verify_player_privacy_pin.dart';
import 'package:footpath_cebu/domain/usecases/reset_player_privacy_pin.dart';
import 'package:footpath_cebu/domain/usecases/cancel_training_session.dart';
import 'package:footpath_cebu/domain/usecases/change_password.dart';
import 'package:footpath_cebu/domain/usecases/reauthenticate.dart';
import 'package:footpath_cebu/domain/usecases/schedule_training_session.dart';
import 'package:footpath_cebu/domain/usecases/update_training_session.dart';
import 'package:footpath_cebu/domain/usecases/update_football_match.dart';
import 'package:footpath_cebu/domain/usecases/unregister_device.dart';
import 'package:footpath_cebu/domain/usecases/upload_player_photo.dart';
import 'package:footpath_cebu/domain/usecases/upload_profile_photo.dart';
import 'package:footpath_cebu/domain/usecases/send_password_reset.dart';
import 'package:footpath_cebu/domain/usecases/sign_in.dart';
import 'package:footpath_cebu/domain/usecases/sign_out.dart';

import 'test_runtime_stub.dart' if (dart.library.io) 'test_runtime_io.dart';

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
/// Live Firebase + Django repositories are the default in every build mode so
/// a normal `flutter run` exercises the same server-authoritative data path as
/// production. Mocks are available only when explicitly requested for
/// isolated UI work with `--dart-define=USE_MOCK=true`. Release builds ignore
/// that flag and always stay live.
const bool mockDataRequestedByBuild = bool.fromEnvironment(
  'USE_MOCK',
  defaultValue: false,
);

bool get useMockData {
  if (kReleaseMode) return false;
  // Flutter's test runner marks its process with FLUTTER_TEST. This keeps
  // existing widget tests deterministic without making ordinary debug runs
  // silently use device-only data.
  if (isFlutterTestRuntime) return true;
  return mockDataRequestedByBuild;
}

// ---------------------------------------------------------------------------
// Data layer — one provider per repository interface.
// ---------------------------------------------------------------------------

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => useMockData ? MockAuthRepository() : FirebaseAuthRepository(),
);

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) =>
      useMockData ? MockNotificationRepository() : ApiNotificationRepository(),
);

final playerRepositoryProvider = Provider<PlayerRepository>(
  (ref) => useMockData
      ? MockPlayerRepository()
      : ApiPlayerRepository(
          unlockTokenFor: ref.watch(playerUnlockTokenStoreProvider).tokenFor,
        ),
);

final playerStatsRepositoryProvider = Provider<PlayerStatsRepository>(
  (ref) => ApiPlayerStatsRepository(),
);

final developmentAssessmentRepositoryProvider =
    Provider<DevelopmentAssessmentRepository>(
      (ref) =>
          ref.watch(playerRepositoryProvider)
              as DevelopmentAssessmentRepository,
    );

/// Coach-only write capability exposed separately from the player read model.
final playerPhotoWriterProvider = Provider<PlayerPhotoWriter>(
  (ref) => ref.watch(playerRepositoryProvider) as PlayerPhotoWriter,
);

final profilePhotoRepositoryProvider = Provider<ProfilePhotoRepository>(
  (ref) =>
      useMockData ? MockProfilePhotoRepository() : ApiProfilePhotoRepository(),
);

final playerUnlockTokenStoreProvider = Provider<PlayerUnlockTokenStore>(
  (ref) => PlayerUnlockTokenStore(),
);

final playerPrivacyPinRepositoryProvider = Provider<PlayerPrivacyPinRepository>(
  (ref) => useMockData
      ? MockPlayerPrivacyPinRepository()
      : ApiPlayerPrivacyPinRepository(),
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
          inner: ApiAttendanceRepository(
            unlockTokenFor: ref.watch(playerUnlockTokenStoreProvider).tokenFor,
          ),
          outbox: ref.watch(attendanceOutboxProvider),
          ownerUid: () => FirebaseAuth.instance.currentUser?.uid,
        ),
);

/// Drains the offline outbox when connectivity returns. Null in mock mode
/// (nothing real to sync). Started once post-login, alongside
/// [registerDeviceProvider].
final attendanceSyncServiceProvider = Provider<AttendanceSyncService?>((ref) {
  if (useMockData) return null;
  final service = AttendanceSyncService(
    outbox: ref.watch(attendanceOutboxProvider),
    inner: ApiAttendanceRepository(
      unlockTokenFor: ref.watch(playerUnlockTokenStoreProvider).tokenFor,
    ),
    ownerUid: () => FirebaseAuth.instance.currentUser?.uid,
  );
  ref.onDispose(service.dispose);
  return service;
});

final trainingRepositoryProvider = Provider<TrainingRepository>(
  (ref) => useMockData ? MockTrainingRepository() : ApiTrainingRepository(),
);

final injuryRepositoryProvider = Provider<InjuryRepository>(
  (ref) => useMockData
      ? MockInjuryRepository()
      : ApiInjuryRepository(
          unlockTokenFor: ref.watch(playerUnlockTokenStoreProvider).tokenFor,
        ),
);

final progressRepositoryProvider = Provider<ProgressRepository>(
  (ref) => useMockData ? MockProgressRepository() : ApiProgressRepository(),
);

final growthRepositoryProvider = Provider<GrowthRepository>(
  (ref) => useMockData
      ? MockGrowthRepository()
      : ApiGrowthRepository(
          unlockTokenFor: ref.watch(playerUnlockTokenStoreProvider).tokenFor,
        ),
);

final matchRepositoryProvider = Provider<MatchRepository>(
  (ref) => useMockData
      ? MockMatchRepository()
      : ApiMatchRepository(
          unlockTokenFor: ref.watch(playerUnlockTokenStoreProvider).tokenFor,
        ),
);

final ageTierRepositoryProvider = Provider<AgeTierRepository>(
  (ref) => useMockData ? MockAgeTierRepository() : ApiAgeTierRepository(),
);

final disputeRepositoryProvider = Provider<DisputeRepository>(
  (ref) => useMockData ? MockDisputeRepository() : ApiDisputeRepository(),
);

final eligibilityHistoryRepositoryProvider =
    Provider<EligibilityHistoryRepository>(
      (ref) => useMockData
          ? MockEligibilityHistoryRepository()
          : ApiEligibilityHistoryRepository(
              unlockTokenFor: ref
                  .watch(playerUnlockTokenStoreProvider)
                  .tokenFor,
            ),
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

final restoreSessionProvider = Provider<RestoreSession>(
  (ref) => RestoreSession(ref.watch(authRepositoryProvider)),
);

final signOutProvider = Provider<SignOut>(
  (ref) => SignOut(
    ref.watch(authRepositoryProvider),
    onSignedOut: () => ref.read(playerUnlockTokenStoreProvider).clear(),
  ),
);

final sendPasswordResetProvider = Provider<SendPasswordReset>(
  (ref) => SendPasswordReset(ref.watch(authRepositoryProvider)),
);

final changePasswordProvider = Provider<ChangePassword>(
  (ref) => ChangePassword(ref.watch(authRepositoryProvider)),
);

final reauthenticateProvider = Provider<Reauthenticate>(
  (ref) => Reauthenticate(ref.watch(authRepositoryProvider)),
);

final getSquadProvider = Provider<GetSquad>(
  (ref) => GetSquad(ref.watch(playerRepositoryProvider)),
);

final getMyProfileProvider = Provider<GetMyProfile>(
  (ref) => GetMyProfile(ref.watch(playerRepositoryProvider)),
);

final getPlayerDetailsProvider = Provider<GetPlayerDetails>(
  (ref) => GetPlayerDetails(
    ref.watch(playerRepositoryProvider) as PlayerDetailsReader,
  ),
);

final getLinkedPlayersProvider = Provider<GetLinkedPlayers>(
  (ref) => GetLinkedPlayers(ref.watch(playerRepositoryProvider)),
);

final getPlayerPrivacyPinStatusProvider = Provider<GetPlayerPrivacyPinStatus>(
  (ref) =>
      GetPlayerPrivacyPinStatus(ref.watch(playerPrivacyPinRepositoryProvider)),
);

final setPlayerPrivacyPinProvider = Provider<SetPlayerPrivacyPin>(
  (ref) => SetPlayerPrivacyPin(ref.watch(playerPrivacyPinRepositoryProvider)),
);

final verifyPlayerPrivacyPinProvider = Provider<VerifyPlayerPrivacyPin>(
  (ref) =>
      VerifyPlayerPrivacyPin(ref.watch(playerPrivacyPinRepositoryProvider)),
);

final resetPlayerPrivacyPinProvider = Provider<ResetPlayerPrivacyPin>(
  (ref) => ResetPlayerPrivacyPin(ref.watch(playerPrivacyPinRepositoryProvider)),
);

final savePlayerAssessmentProvider = Provider<SavePlayerAssessment>(
  (ref) => SavePlayerAssessment(ref.watch(playerRepositoryProvider)),
);

final getDevelopmentAssessmentFormProvider =
    Provider<GetDevelopmentAssessmentForm>(
      (ref) => GetDevelopmentAssessmentForm(
        ref.watch(developmentAssessmentRepositoryProvider),
      ),
    );

final saveDevelopmentAssessmentProvider = Provider<SaveDevelopmentAssessment>(
  (ref) => SaveDevelopmentAssessment(
    ref.watch(developmentAssessmentRepositoryProvider),
  ),
);

final savePlayerPositionProvider = Provider<SavePlayerPosition>(
  (ref) => SavePlayerPosition(ref.watch(playerRepositoryProvider)),
);

final uploadPlayerPhotoProvider = Provider<UploadPlayerPhoto>(
  (ref) => UploadPlayerPhoto(ref.watch(playerPhotoWriterProvider)),
);

final uploadProfilePhotoProvider = Provider<UploadProfilePhoto>(
  (ref) => UploadProfilePhoto(ref.watch(profilePhotoRepositoryProvider)),
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

final getEligibilityHistoryProvider = Provider<GetEligibilityHistory>(
  (ref) =>
      GetEligibilityHistory(ref.watch(eligibilityHistoryRepositoryProvider)),
);

final raiseDisputeProvider = Provider<RaiseDispute>(
  (ref) => RaiseDispute(ref.watch(disputeRepositoryProvider)),
);

final respondToDisputeProvider = Provider<RespondToDispute>(
  (ref) => RespondToDispute(ref.watch(disputeRepositoryProvider)),
);

final getSessionConfirmationsProvider = Provider<GetSessionConfirmations>(
  (ref) =>
      GetSessionConfirmations(ref.watch(sessionConfirmationRepositoryProvider)),
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

final getSquadProgressProvider = Provider<GetSquadProgress>(
  (ref) => GetSquadProgress(ref.watch(progressRepositoryProvider)),
);

final getFootballMatchesProvider = Provider<GetFootballMatches>(
  (ref) => GetFootballMatches(ref.watch(matchRepositoryProvider)),
);

final createFootballMatchProvider = Provider<CreateFootballMatch>(
  (ref) => CreateFootballMatch(ref.watch(matchRepositoryProvider)),
);

final updateFootballMatchProvider = Provider<UpdateFootballMatch>(
  (ref) => UpdateFootballMatch(ref.watch(matchRepositoryProvider)),
);

final getMatchPerformancesProvider = Provider<GetMatchPerformances>(
  (ref) => GetMatchPerformances(ref.watch(matchRepositoryProvider)),
);

final tournamentScheduleRepositoryProvider =
    Provider<TournamentScheduleRepository>(
      (ref) => useMockData
          ? MockTournamentScheduleRepository()
          : ApiTournamentScheduleRepository(),
    );

final tournamentRosterRepositoryProvider = Provider<TournamentRosterRepository>(
  (ref) => useMockData
      ? MockTournamentRosterRepository()
      : ApiTournamentRosterRepository(),
);

final getMatchRosterProvider = Provider<GetMatchRoster>(
  (ref) => GetMatchRoster(ref.watch(matchRepositoryProvider)),
);

final getPlayerMatchStatisticsProvider = Provider<GetPlayerMatchStatistics>(
  (ref) => GetPlayerMatchStatistics(ref.watch(matchRepositoryProvider)),
);

final saveMatchPerformanceProvider = Provider<SaveMatchPerformance>(
  (ref) => SaveMatchPerformance(ref.watch(matchRepositoryProvider)),
);

final deleteMatchPerformanceProvider = Provider<DeleteMatchPerformance>(
  (ref) => DeleteMatchPerformance(ref.watch(matchRepositoryProvider)),
);

final saveMatchRatingProvider = Provider<SaveMatchRating>(
  (ref) => SaveMatchRating(ref.watch(matchRepositoryProvider)),
);

final deleteMatchRatingProvider = Provider<DeleteMatchRating>(
  (ref) => DeleteMatchRating(ref.watch(matchRepositoryProvider)),
);

final getAgeTierBandsProvider = Provider<GetAgeTierBands>(
  (ref) => GetAgeTierBands(ref.watch(ageTierRepositoryProvider)),
);

final updateTrainingSessionProvider = Provider<UpdateTrainingSession>(
  (ref) => UpdateTrainingSession(ref.watch(trainingRepositoryProvider)),
);

final cancelTrainingSessionProvider = Provider<CancelTrainingSession>(
  (ref) => CancelTrainingSession(ref.watch(trainingRepositoryProvider)),
);

final registerDeviceProvider = Provider<RegisterDevice>(
  (ref) => RegisterDevice(ref.watch(deviceRepositoryProvider)),
);

final unregisterDeviceProvider = Provider<UnregisterDevice>(
  (ref) => UnregisterDevice(ref.watch(deviceRepositoryProvider)),
);
