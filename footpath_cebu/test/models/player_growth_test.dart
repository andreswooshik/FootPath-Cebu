import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/entities/player_growth.dart';

void main() {
  test('parses typed assessment and categorized training growth', () {
    final growth = PlayerGrowth.fromJson({
      'playerId': '12',
      'playerName': 'Alex Santos',
      'position': 'CM',
      'assessments': {
        'summary': {
          'sampleSize': 2,
          'latestOverall': 78,
          'previousOverall': 74,
          'overallDelta': 4,
          'attributeDeltas': {'passing': 6},
          'classification': 'IMPROVING',
        },
        'history': [
          {
            'id': '3',
            'playerId': '12',
            'position': 'CM',
            'ratings': {
              'pace': 75,
              'shooting': 72,
              'passing': 84,
              'dribbling': 80,
              'defending': 76,
              'physical': 81,
            },
            'overall': 78,
            'coachNotes': 'Improved scanning before receiving.',
            'assessmentReason': 'MONTHLY_REVIEW',
            'createdAt': '2026-08-29T06:30:00Z',
            'assessedByRole': 'Coach',
          },
        ],
      },
      'training': {
        'groups': [
          {
            'focus': 'TECHNICAL',
            'sampleSize': 4,
            'presentCount': 3,
            'attendanceRate': 75,
            'averageEffort': 86,
            'averagePerformanceScore': '8.4',
            'comparison': {
              'metric': 'PERFORMANCE_SCORE',
              'recentSampleSize': 2,
              'previousSampleSize': 2,
              'performanceDelta': 0.7,
              'effortDelta': 3,
              'classification': 'IMPROVING',
            },
            'history': [
              {
                'playerId': '12',
                'sessionId': '8',
                'sessionName': 'First touch',
                'sessionFocus': 'TECHNICAL',
                'sessionDate': '2026-08-28',
                'status': 'PRESENT',
                'effort': 88,
                'performanceScore': '8.7',
                'note': 'Cleaner first touch.',
                'updatedAt': '2026-08-28T10:00:00Z',
              },
            ],
          },
        ],
      },
      'regularMatches': null,
      'tournaments': {'groups': []},
    });

    expect(growth.assessmentSummary!.overallDelta, 4);
    expect(
      growth.assessmentSummary!.classification,
      GrowthClassification.improving,
    );
    expect(growth.assessments.single.reason, AssessmentReason.monthlyReview);
    expect(growth.assessments.single.ratings.passing, 84);
    expect(growth.training.single.focus, 'TECHNICAL');
    expect(growth.training.single.averagePerformanceScore, 8.4);
    expect(growth.training.single.performanceDelta, 0.7);
    expect(growth.training.single.comparisonMetric, 'PERFORMANCE_SCORE');
    expect(growth.training.single.history.single.performanceScore, 8.7);
    expect(
      growth.training.single.history.single.sessionDate,
      DateTime(2026, 8, 28),
    );
  });

  test('old attendance JSON remains valid without a performance score', () {
    final attendance = Attendance.fromJson({
      'playerId': '12',
      'status': 'PRESENT',
      'effort': 80,
      'note': 'Legacy queued record',
      'updatedAt': '2026-08-20T10:00:00Z',
    });

    expect(attendance.performanceScore, isNull);
    expect(attendance.effort, 80);
    expect(attendance.toJson(), isNot(contains('performanceScore')));
  });

  test('growth queries compare by all shared filter values', () {
    final from = DateTime(2026, 7, 1);
    final to = DateTime(2026, 7, 31);
    final first = GrowthQuery(
      playerId: '12',
      range: GrowthRange.last30Days,
      category: GrowthCategory.training,
      from: from,
      to: to,
    );
    final same = GrowthQuery(
      playerId: '12',
      range: GrowthRange.last30Days,
      category: GrowthCategory.training,
      from: from,
      to: to,
    );

    expect(first, same);
    expect(first.hashCode, same.hashCode);
    expect(first, isNot(const GrowthQuery(playerId: '12')));
  });
}
