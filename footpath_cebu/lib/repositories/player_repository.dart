import '../models/player.dart';

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

/// Aggregate of the player-domain reads. Concrete data sources implement this
/// one interface (all reads live together), while each ViewModel depends only
/// on the narrow interface it actually uses (Interface Segregation) — so a
/// Coach ViewModel can't reach the guardian's or player's reads.
abstract class PlayerRepository
    implements
        SquadRepository,
        PlayerProfileRepository,
        LinkedPlayersRepository {}

/// Thrown when a player-domain read cannot be completed.
class PlayerRepositoryException implements Exception {
  PlayerRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}
