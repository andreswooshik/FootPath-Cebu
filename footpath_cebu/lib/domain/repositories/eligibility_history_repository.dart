import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/eligibility_change.dart';

/// Reads a player's academic-eligibility transition history. History rows are
/// written server-side by the eligibility-change signal, never by a client.
abstract class EligibilityHistoryRepository {
  /// Returns the player's eligibility transitions, newest first.
  Future<List<EligibilityChange>> fetchHistoryForPlayer(
    String playerId, {
    String? unlockToken,
  });

  /// Records a Coordinator or School Staff eligibility decision. The backend
  /// owns role, school-affiliation, club-scope, history, and notifications.
  Future<EligibilityStatus> updateEligibility(
    String playerId,
    EligibilityStatus status,
  );
}

/// Thrown when the history cannot be read.
class EligibilityHistoryRepositoryException implements Exception {
  EligibilityHistoryRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}
