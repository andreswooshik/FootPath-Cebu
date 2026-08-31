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
        'framework': _framework(),
        'developmentSummary': {
          'sampleSize': 2,
          'latestAssessmentId': 'd2',
          'previousAssessmentId': 'd1',
          'domains': [
            for (final entry in _domainLabels.entries)
              {
                'key': entry.key,
                'label': entry.value,
                'latestScore': 4.0,
                'previousScore': 3.0,
                'delta': 1.0,
                'comparableIndicatorCount': 3,
                'indicatorDeltas': const {},
                'classification': 'IMPROVING',
              },
          ],
        },
        'developmentHistory': [
          _developmentAssessment('d2', now, 4, 'MONTHLY_REVIEW'),
          _developmentAssessment(
            'd1',
            now.subtract(const Duration(days: 30)),
            3,
            'GENERAL_REVIEW',
          ),
        ],
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

const _domainLabels = {
  'technical': 'Technical',
  'tactical': 'Tactical / Game Intelligence',
  'physical': 'Physical / Coordinative',
  'mental': 'Mental / Emotional',
  'socialValues': 'Social / Values',
};

Map<String, dynamic> _framework() => {
  'version': 1,
  'name': 'FootPath Development Framework',
  'methodology': 'Holistic player development.',
  'disclaimer': 'A FootPath framework.',
  'ageTier': 'DEVELOPMENT',
  'position': 'CM',
  'positionGroup': 'MIDFIELD',
  'scale': const [],
  'domains': [
    for (final entry in _domainLabels.entries)
      {
        'key': entry.key,
        'label': entry.value,
        'description': '',
        'guidance': '',
        'minimumObserved': 1,
        'indicators': const [],
      },
  ],
};

Map<String, dynamic> _developmentAssessment(
  String id,
  DateTime date,
  int score,
  String reason,
) => {
  'id': id,
  'playerId': 'p1',
  'position': 'CM',
  'ageTier': 'DEVELOPMENT',
  'ageAtAssessment': 15,
  'frameworkVersion': 1,
  'ratings': {
    for (final key in _domainLabels.keys)
      key: {'exampleOne': score, 'exampleTwo': score, 'exampleThree': score},
  },
  'domainScores': {for (final key in _domainLabels.keys) key: score.toDouble()},
  'strengths': 'Scans early and supports teammates.',
  'developmentTargets': 'Receive on the weaker side more often.',
  'coachNotes': 'Good month-to-month progress.',
  'assessmentReason': reason,
  'createdAt': date.toIso8601String(),
};

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
