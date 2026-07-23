import 'package:footpath_cebu/domain/entities/player_progress.dart';

/// Reads the squad's per-player progress aggregates (coach only,
/// server-enforced).
abstract class ProgressRepository {
  Future<List<PlayerProgress>> fetchSquadProgress();
}

/// Thrown when the squad progress cannot be loaded.
class ProgressRepositoryException implements Exception {
  ProgressRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}
