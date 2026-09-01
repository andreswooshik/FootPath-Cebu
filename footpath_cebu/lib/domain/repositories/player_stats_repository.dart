import 'package:footpath_cebu/domain/entities/player_stats.dart';

abstract class PlayerStatsRepository {
  Future<PlayerStats> fetchStats(String playerId, {bool forceRefresh = false});
  Future<PlayerStatsSaveResult> saveAssessment(
    String playerId,
    PlayerStatsDraft draft,
  );
}

class PlayerStatsRepositoryException implements Exception {
  const PlayerStatsRepositoryException(this.message);
  final String message;
  @override
  String toString() => message;
}
