import 'package:footpath_cebu/domain/entities/session_confirmation.dart';

/// Reads a player's session confirmations — used by the player's own
/// schedule view.
abstract class SessionConfirmationReader {
  /// Returns every confirmation the player has recorded, most recent first.
  Future<List<SessionConfirmation>> fetchConfirmationsForPlayer(
    String playerId,
  );
}

/// Records a player's RSVP for one session. Kept separate from the reader —
/// Interface Segregation.
abstract class SessionConfirmationWriter {
  /// Creates or replaces the player's response for [sessionId].
  Future<SessionConfirmation> confirmSession(
    String sessionId,
    String playerId,
    ConfirmationStatus status,
  );
}

/// Aggregate of the confirmation reads and writes. Concrete data sources
/// implement this one interface; each consumer depends only on the narrow
/// interface it actually uses.
abstract class SessionConfirmationRepository
    implements SessionConfirmationReader, SessionConfirmationWriter {}

/// Thrown when a confirmation read or write cannot be completed.
class SessionConfirmationRepositoryException implements Exception {
  SessionConfirmationRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}