import 'package:footpath_cebu/data/repositories/api_player_repository.dart';
import 'package:footpath_cebu/data/repositories/api_training_repository.dart';
import 'package:footpath_cebu/data/repositories/firebase_auth_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_auth_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_player_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_training_repository.dart';
import 'package:footpath_cebu/domain/repositories/auth_repository.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';
import 'package:footpath_cebu/domain/repositories/training_repository.dart';
import 'package:footpath_cebu/domain/usecases/get_linked_players.dart';
import 'package:footpath_cebu/domain/usecases/get_my_profile.dart';
import 'package:footpath_cebu/domain/usecases/get_squad.dart';
import 'package:footpath_cebu/domain/usecases/get_training_sessions.dart';
import 'package:footpath_cebu/domain/usecases/schedule_training_session.dart';
import 'package:footpath_cebu/domain/usecases/send_password_reset.dart';
import 'package:footpath_cebu/domain/usecases/sign_in.dart';
import 'package:footpath_cebu/domain/usecases/sign_out.dart';

/// Composition root (the outermost layer). Builds the concrete data-layer
/// repositories and wires the domain use cases the presentation layer depends
/// on. Swapping mock <-> live happens here and nowhere else.
class ServiceLocator {
  ServiceLocator._();

  static late SignIn signIn;
  static late SignOut signOut;
  static late SendPasswordReset sendPasswordReset;
  static late GetSquad getSquad;
  static late GetMyProfile getMyProfile;
  static late GetLinkedPlayers getLinkedPlayers;
  static late GetTrainingSessions getTrainingSessions;
  static late ScheduleTrainingSession scheduleTrainingSession;

  /// Mock repositories for UI development without a backend.
  static void initMock() => _wire(
        MockAuthRepository(),
        MockPlayerRepository(),
        MockTrainingRepository(),
      );

  /// Live Firebase auth + Django REST repositories.
  static void initFirebase() => _wire(
        FirebaseAuthRepository(),
        ApiPlayerRepository(),
        ApiTrainingRepository(),
      );

  static void _wire(
    AuthRepository auth,
    PlayerRepository players,
    TrainingRepository training,
  ) {
    signIn = SignIn(auth);
    signOut = SignOut(auth);
    sendPasswordReset = SendPasswordReset(auth);
    getSquad = GetSquad(players);
    getMyProfile = GetMyProfile(players);
    getLinkedPlayers = GetLinkedPlayers(players);
    getTrainingSessions = GetTrainingSessions(training);
    scheduleTrainingSession = ScheduleTrainingSession(training);
  }
}
