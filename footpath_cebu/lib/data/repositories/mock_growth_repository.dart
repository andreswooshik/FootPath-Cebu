import 'package:footpath_cebu/domain/entities/player_growth.dart';
import 'package:footpath_cebu/domain/repositories/growth_repository.dart';

class MockGrowthRepository implements GrowthRepository {
  @override
  Future<PlayerGrowth> fetchGrowth(GrowthQuery query) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final now = DateTime.now();
    return PlayerGrowth.fromJson({
      'playerId': query.playerId,
      'playerName': 'Rhobert Ronaldo',
      'position': 'ST',
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
      'regularMatches': _regularMatches(now),
      'tournaments': {
        'groups': [_tournamentMatches(now)],
      },
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
  'ageTier': 'PATHWAY',
  'position': 'ST',
  'positionGroup': 'FORWARD',
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
  'position': 'ST',
  'ageTier': 'PATHWAY',
  'ageAtAssessment': 16,
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
  'position': 'ST',
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

Map<String, dynamic> _regularMatches(DateTime now) {
  final latest = _matchPerformance(
    id: 'perf-m1-p1',
    opponent: 'Cebu United',
    competition: 'Cebu Youth League',
    date: now.subtract(const Duration(days: 7)),
    category: 'LEAGUE',
    ourScore: 3,
    opponentScore: 1,
    rating: 8.7,
    goals: 2,
    assists: 1,
    passesAttempted: 28,
    passesCompleted: 22,
    tackles: 1,
  );
  final previous = _matchPerformance(
    id: 'perf-m2-p1',
    opponent: 'Mandaue FC',
    competition: 'Cebu Youth League',
    date: now.subtract(const Duration(days: 21)),
    category: 'LEAGUE',
    ourScore: 1,
    opponentScore: 1,
    rating: 7.4,
    goals: 0,
    assists: 1,
    passesAttempted: 30,
    passesCompleted: 23,
    tackles: 2,
  );
  return {
    'sampleSize': 2,
    'summary': _matchSummary(
      matches: 2,
      minutes: 160,
      goals: 2,
      assists: 2,
      passesAttempted: 58,
      passesCompleted: 45,
      tackles: 3,
      rating: 8.05,
    ),
    'metrics': {
      'averageRating': _growthMetric(8.7, 7.4),
      'passCompletionRate': _growthMetric(78.6, 76.7),
      'goalsPer90': _growthMetric(2.25, 0),
      'assistsPer90': _growthMetric(1.125, 1.125),
      'tacklesInterceptionsPer90': _growthMetric(1.125, 2.25),
    },
    'history': [latest, previous],
  };
}

Map<String, dynamic> _tournamentMatches(DateTime now) {
  final performance = _matchPerformance(
    id: 'perf-m3-p1',
    opponent: 'Lapu-Lapu Academy',
    competition: 'Cebu Youth Cup',
    date: now.subtract(const Duration(days: 35)),
    category: 'TOURNAMENT',
    ourScore: 1,
    opponentScore: 2,
    rating: 6.9,
    goals: 0,
    assists: 0,
    passesAttempted: 27,
    passesCompleted: 18,
    tackles: 1,
  );
  final summary = _matchSummary(
    matches: 1,
    minutes: 80,
    goals: 0,
    assists: 0,
    passesAttempted: 27,
    passesCompleted: 18,
    tackles: 1,
    rating: 6.9,
  );
  return {
    'tournamentId': 'cup-1',
    'tournament': 'Cebu Youth Cup',
    'ageBracketLabel': 'U18',
    'sampleSize': 1,
    'summary': summary,
    'teamRecord': {'wins': 0, 'draws': 0, 'losses': 1},
    'growth': {
      'sampleSize': 1,
      'summary': summary,
      'metrics': <String, dynamic>{},
      'history': [performance],
    },
    'history': [performance],
  };
}

Map<String, dynamic> _growthMetric(double recent, double previous) => {
  'recent': recent,
  'previous': previous,
  'delta': recent - previous,
  'classification': recent > previous
      ? 'IMPROVING'
      : recent < previous
      ? 'NEEDS_ATTENTION'
      : 'STABLE',
};

Map<String, dynamic> _matchSummary({
  required int matches,
  required int minutes,
  required int goals,
  required int assists,
  required int passesAttempted,
  required int passesCompleted,
  required int tackles,
  required double rating,
}) => {
  'matchesPlayed': matches,
  'starts': matches,
  'minutesPlayed': minutes,
  'goals': goals,
  'assists': assists,
  'shots': 10,
  'shotsOnTarget': 6,
  'passesAttempted': passesAttempted,
  'passesCompleted': passesCompleted,
  'passCompletionRate': passesCompleted * 100 / passesAttempted,
  'tackles': tackles,
  'interceptions': 1,
  'yellowCards': 0,
  'redCards': 0,
  'saves': 0,
  'goalsConceded': 0,
  'cleanSheets': 0,
  'averageRating': rating,
};

Map<String, dynamic> _matchPerformance({
  required String id,
  required String opponent,
  required String competition,
  required DateTime date,
  required String category,
  required int ourScore,
  required int opponentScore,
  required double rating,
  required int goals,
  required int assists,
  required int passesAttempted,
  required int passesCompleted,
  required int tackles,
}) => {
  'id': id,
  'playerId': 'p1',
  'playerName': 'Rhobert Ronaldo',
  'match': {
    'id': id.replaceFirst('perf-', '').replaceFirst('-p1', ''),
    'opponent': opponent,
    'competition': competition,
    'playedOn': date.toIso8601String(),
    'venue': category == 'TOURNAMENT' ? 'NEUTRAL' : 'HOME',
    'ourScore': ourScore,
    'opponentScore': opponentScore,
    'category': category,
    if (category == 'TOURNAMENT') 'ageBracketLabel': 'U18',
  },
  'position': 'ST',
  'starter': true,
  'minutesPlayed': 80,
  'goals': goals,
  'assists': assists,
  'shots': 5,
  'shotsOnTarget': 3,
  'passesAttempted': passesAttempted,
  'passesCompleted': passesCompleted,
  'tackles': tackles,
  'interceptions': 0,
  'yellowCards': 0,
  'redCards': 0,
  'saves': 0,
  'goalsConceded': 0,
  'cleanSheet': false,
  'coachRating': rating,
  'notes': 'Strong movement and decision-making.',
  'ratingStatus': 'RATED',
};
