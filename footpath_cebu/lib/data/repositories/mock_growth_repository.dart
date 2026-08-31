import 'package:footpath_cebu/domain/entities/player_growth.dart';
import 'package:footpath_cebu/domain/repositories/growth_repository.dart';

class MockGrowthRepository implements GrowthRepository {
  @override
  Future<PlayerGrowth> fetchGrowth(GrowthQuery query) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final now = DateTime.now();
    return PlayerGrowth.fromJson({
      'playerId': query.playerId,
      'playerName': 'Demo Player',
      'position': 'CM',
      'assessments': {
        'summary': {
          'sampleSize': 2,
          'latestOverall': 76,
          'previousOverall': 72,
          'overallDelta': 4,
          'attributeDeltas': {'pace': 3, 'passing': 5},
          'classification': 'IMPROVING',
        },
        'history': [
          _assessment('a2', now, 76, 'MONTHLY_REVIEW'),
          _assessment(
            'a1',
            now.subtract(const Duration(days: 30)),
            72,
            'BASELINE',
          ),
        ],
      },
      'training': {
        'groups': [
          for (final focus in ['TECHNICAL', 'PHYSICAL', 'MENTAL'])
            {
              'focus': focus,
              'sampleSize': focus == 'TECHNICAL' ? 4 : 0,
              'presentCount': focus == 'TECHNICAL' ? 4 : 0,
              'attendanceRate': focus == 'TECHNICAL' ? 100.0 : null,
              'averageEffort': focus == 'TECHNICAL' ? 84.0 : null,
              'averagePerformanceScore': focus == 'TECHNICAL' ? 8.1 : null,
              'comparison': {
                'metric': 'PERFORMANCE_SCORE',
                'recentSampleSize': focus == 'TECHNICAL' ? 2 : 0,
                'previousSampleSize': focus == 'TECHNICAL' ? 2 : 0,
                'performanceDelta': focus == 'TECHNICAL' ? 0.6 : null,
                'effortDelta': focus == 'TECHNICAL' ? 4.0 : null,
                'classification': focus == 'TECHNICAL'
                    ? 'IMPROVING'
                    : 'INSUFFICIENT_DATA',
              },
              'history': const [],
            },
        ],
      },
      'regularMatches': _emptyMatches(),
      'tournaments': {'groups': const []},
    });
  }
}

Map<String, dynamic> _assessment(
  String id,
  DateTime date,
  int overall,
  String reason,
) => {
  'id': id,
  'playerId': 'p1',
  'position': 'CM',
  'ratings': {
    'pace': overall,
    'shooting': overall,
    'passing': overall,
    'dribbling': overall,
    'defending': overall,
    'physical': overall,
    'diving': 0,
    'handling': 0,
    'kicking': 0,
    'reflexes': 0,
    'speed': 0,
    'positioning': 0,
  },
  'overall': overall,
  'coachNotes': reason == 'BASELINE' ? '' : 'Good month-to-month progress.',
  'assessmentReason': reason,
  'createdAt': date.toIso8601String(),
};

Map<String, dynamic> _emptyMatches() => {
  'sampleSize': 0,
  'summary': <String, dynamic>{},
  'metrics': <String, dynamic>{},
  'history': <Map<String, dynamic>>[],
};
