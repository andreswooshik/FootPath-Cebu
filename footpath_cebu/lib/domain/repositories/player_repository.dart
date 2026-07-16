import 'package:footpath_cebu/domain/entities/player.dart';

/// Squad roster reads — used by the Coach dashboard.
abstract class SquadRepository {
  /// Returns every player registered to the coach's squad.
  Future<List<Player>> fetchSquad();
}

/// The signed-in player's own profile — used by the Player dashboard.
abstract class PlayerProfileRepository {
  Future<Player> fetchMyProfile();
}

/// The players linked to the signed-in guardian — used by the Guardian
/// dashboard.
abstract class LinkedPlayersRepository {
  Future<List<Player>> fetchLinkedPlayers();
}

/// Persists a coach's performance assessment (the six ratings) for a player and
/// returns the updated player — used by the coach's assessment form.
abstract class AssessmentWriter {
  Future<Player> saveAssessment(String playerId, PlayerRatings ratings);
}

/// Aggregate of the player-domain reads and writes. Concrete data sources
/// implement this one interface, while each presentation provider depends only
/// on the narrow interface it actually uses (Interface Segregation) — so the
/// Coach's providers can't reach the guardian's or player's reads.
abstract class PlayerRepository
    implements
        SquadRepository,
        PlayerProfileRepository,
        LinkedPlayersRepository,
        AssessmentWriter {}

/// Thrown when a player-domain read cannot be completed.
class PlayerRepositoryException implements Exception {
  PlayerRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}
