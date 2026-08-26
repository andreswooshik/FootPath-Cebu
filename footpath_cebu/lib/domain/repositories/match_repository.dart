import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/match_performance.dart';

/// Read capability shared by players and authorized family/coaching staff.
abstract interface class MatchStatisticsReader {
  Future<PlayerMatchStatistics> fetchPlayerStatistics(String playerId);
}

/// Coach-only match management capability.
abstract interface class MatchManager {
  Future<List<FootballMatch>> fetchMatches();

  Future<FootballMatch> createMatch(FootballMatchDraft draft);

  Future<FootballMatch> updateMatch(String matchId, FootballMatchDraft draft);

  Future<List<MatchPerformance>> fetchMatchPerformances(String matchId);

  Future<MatchPerformance> savePerformance(
    String matchId,
    String playerId,
    MatchPerformanceDraft draft,
  );

  Future<void> deletePerformance(String matchId, String playerId);
}

abstract interface class MatchRepository
    implements MatchStatisticsReader, MatchManager {}

class MatchRepositoryException implements Exception {
  const MatchRepositoryException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
