import '../models/player.dart';

/// Abstract interface for reading the squad roster.
///
/// The ViewModel depends on this interface — never on a concrete Firebase or
/// HTTP implementation — so the UI can be developed and tested against mocks.
abstract class PlayerRepository {
  /// Returns every player registered to the coach's squad.
  Future<List<Player>> fetchSquad();

  /// Returns the signed-in player's own profile (Player dashboard).
  Future<Player> fetchMyProfile();

  /// Returns the players linked to the signed-in guardian (Guardian dashboard).
  Future<List<Player>> fetchLinkedPlayers();
}

/// Thrown when the roster cannot be loaded.
class PlayerRepositoryException implements Exception {
  PlayerRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}
