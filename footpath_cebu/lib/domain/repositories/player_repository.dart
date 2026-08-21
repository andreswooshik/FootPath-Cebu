import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';

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

/// A sensitive player profile read. Guardian callers must provide the
/// short-lived server-issued privacy unlock grant.
abstract class PlayerDetailsReader {
  Future<Player> fetchPlayerDetails(String playerId, {String? unlockToken});
}

/// Persists a coach's performance assessment — the six ratings *and* the
/// written evaluation — for a player, and returns the updated player. Used by
/// the coach's assessment form.
abstract class AssessmentWriter {
  /// [coachNotes] is required rather than optional on purpose: the form once
  /// rendered a notes field that no layer carried, so it was silently
  /// discarded on save. Making it required means the compiler, not a demo,
  /// catches the next caller that forgets it. Pass `''` to clear the note.
  Future<Player> saveAssessment(
    String playerId,
    PlayerRatings ratings, {
    required String coachNotes,
  });
}

/// Persists the position a coach assigned to a player and returns the updated
/// player — used by the coach's position picker. Separate from
/// [AssessmentWriter]: a position is the player's identity, not one of the six
/// ratings, and only a coach may set it.
abstract class PositionWriter {
  Future<Player> savePosition(String playerId, PlayerPosition position);
}

/// Replaces a player's roster photo. Kept separate from [PlayerRepository] so
/// read-only player consumers do not gain access to a Coach-only write.
abstract class PlayerPhotoWriter {
  Future<Player> uploadPhoto(
    String playerId, {
    required List<int> bytes,
    required String filename,
    required String contentType,
  });
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
        AssessmentWriter,
        PositionWriter {}

/// Thrown when a player-domain read cannot be completed.
class PlayerRepositoryException implements Exception {
  PlayerRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}
