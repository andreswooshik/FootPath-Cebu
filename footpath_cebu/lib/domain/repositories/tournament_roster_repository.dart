import 'package:footpath_cebu/domain/entities/tournament_roster.dart';

abstract interface class TournamentRosterRepository {
  Future<TournamentSquad> fetchSquad(String bracketId);
  Future<List<TournamentRosterCandidate>> fetchCandidates(String bracketId);
  Future<TournamentSquad> saveSquad(
    String bracketId,
    List<TournamentRosterSelection> entries,
  );
  Future<TournamentSquad> publishSquad(String bracketId);
}

class TournamentRosterRepositoryException implements Exception {
  const TournamentRosterRepositoryException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
