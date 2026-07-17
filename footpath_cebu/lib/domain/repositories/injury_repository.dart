import 'package:footpath_cebu/domain/entities/injury_record.dart';

/// Reads a player's injury history — used by the player's own screen and the
/// coach's read-only view.
abstract class InjuryReader {
  /// Returns the player's injuries, most recent first.
  Future<List<InjuryRecord>> fetchInjuriesForPlayer(String playerId);
}

/// Writes injury records. Kept separate from the reader so the coach's
/// view-only screen cannot depend on a write it must never perform —
/// Interface Segregation.
abstract class InjuryWriter {
  /// Creates (id == null) or updates (id set) one record. Returns the saved
  /// record as the server stored it.
  Future<InjuryRecord> saveInjury(InjuryRecord record);

  Future<void> deleteInjury(String injuryId);
}

/// Aggregate of the injury reads and writes. Concrete data sources implement
/// this one interface; each consumer depends only on the narrow interface it
/// actually uses.
abstract class InjuryRepository implements InjuryReader, InjuryWriter {}

/// Thrown when an injury read or write cannot be completed.
class InjuryRepositoryException implements Exception {
  InjuryRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}
