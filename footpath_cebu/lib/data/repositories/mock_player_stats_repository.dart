import 'package:footpath_cebu/domain/entities/player_stats.dart';
import 'package:footpath_cebu/domain/repositories/player_stats_repository.dart';

class MockPlayerStatsRepository implements PlayerStatsRepository {
  @override
  Future<PlayerStats> fetchStats(
    String playerId, {
    bool forceRefresh = false,
  }) async => PlayerStats.fromJson({
    'catalog': {
      'version': 1,
      'position': 'ST',
      'roleGroup': 'ATTACKER',
      'attributes': [
        'Pace',
        'Shooting',
        'Dribbling',
        'Off-ball Movement',
        'Passing',
        'Physical',
      ],
    },
    'latestCompatibleStats': {
      'id': 'stats-1',
      'position': 'ST',
      'roleGroup': 'ATTACKER',
      'catalogVersion': 1,
      'scores': {
        'pace': 82,
        'shooting': 84,
        'dribbling': 79,
        'off_ball_movement': 81,
        'passing': 76,
        'physical': 78,
      },
      'overall': 80,
      'reason': 'MONTHLY_REVIEW',
      'coachNotes': 'Strong movement and finishing.',
      'assessedBy': 'Coach Reyes',
      'createdAt': '2026-08-20T08:00:00Z',
    },
    'comparison': {
      'baseline': false,
      'previousOverall': 77,
      'newOverall': 80,
      'overallDelta': 3,
      'attributes': {},
    },
    'history': [],
    'legacyStatsHistory': [],
    'isBaseline': false,
  });

  @override
  Future<PlayerStatsSaveResult> saveAssessment(
    String playerId,
    PlayerStatsDraft draft,
  ) => throw const PlayerStatsRepositoryException('Mock save not configured.');
}
