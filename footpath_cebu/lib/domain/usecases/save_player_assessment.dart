import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';

/// Use case: persist a coach's performance assessment for one player.
///
/// Depends on the narrow [AssessmentWriter] (Interface Segregation) — it can
/// write ratings but cannot reach any read.
class SavePlayerAssessment {
  const SavePlayerAssessment(this._repository);

  final AssessmentWriter _repository;

  Future<Player> call(
    String playerId,
    PlayerRatings ratings, {
    required String coachNotes,
  }) =>
      _repository.saveAssessment(playerId, ratings, coachNotes: coachNotes);
}
