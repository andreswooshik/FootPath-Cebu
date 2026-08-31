import 'package:flutter_test/flutter_test.dart';

import 'package:footpath_cebu/domain/entities/development_assessment.dart';

Map<String, dynamic> _frameworkJson() => {
  'version': 1,
  'name': 'FootPath Development Framework',
  'methodology': 'Holistic development.',
  'disclaimer': 'A FootPath framework.',
  'ageTier': 'DEVELOPMENT',
  'position': 'CM',
  'positionGroup': 'MIDFIELD',
  'scale': [
    {'value': 1, 'label': 'Emerging', 'description': 'Needs support.'},
    {
      'value': null,
      'label': 'Not observed',
      'description': 'Not enough evidence.',
    },
  ],
  'domains': [
    {
      'key': 'technical',
      'label': 'Technical',
      'description': 'Football actions.',
      'guidance': 'Use recent evidence.',
      'minimumObserved': 2,
      'indicators': [
        {
          'key': 'firstTouch',
          'label': 'First touch',
          'description': 'Controls the ball.',
          'scope': 'CORE',
        },
        {
          'key': 'progressivePassing',
          'label': 'Progressive passing',
          'description': 'Finds forward options.',
          'scope': 'POSITION',
        },
      ],
    },
  ],
};

Map<String, dynamic> _snapshotJson() => {
  'id': 'a1',
  'playerId': '7',
  'position': 'CM',
  'ageTier': 'DEVELOPMENT',
  'ageAtAssessment': 15,
  'frameworkVersion': 1,
  'ratings': {
    'technical': {'firstTouch': 4, 'progressivePassing': null},
  },
  'domainScores': {'technical': 4.0},
  'strengths': 'Receives on the half-turn.',
  'developmentTargets': 'Scan the far side earlier.',
  'coachNotes': 'Good response to feedback.',
  'assessmentReason': 'MONTHLY_REVIEW',
  'createdAt': '2026-08-30T08:00:00Z',
};

void main() {
  test('parses framework, Not Observed, and immutable assessment history', () {
    final form = DevelopmentAssessmentFormData.fromJson({
      'framework': _frameworkJson(),
      'latestAssessment': _snapshotJson(),
    });

    expect(form.framework.domains.single.minimumObserved, 2);
    expect(form.framework.domains.single.indicators.last.scope, 'POSITION');
    expect(form.framework.scale.last.value, isNull);
    expect(form.latestAssessment!.ratings.score('technical', 'firstTouch'), 4);
    expect(
      form.latestAssessment!.ratings.score('technical', 'progressivePassing'),
      isNull,
    );
    expect(form.latestAssessment!.ratings.average('technical'), 4.0);
    expect(form.latestAssessment!.domainScores['technical'], 4.0);
  });

  test('draft JSON uses only the five-domain wire contract', () {
    final draft = DevelopmentAssessmentDraft(
      frameworkVersion: 1,
      ratings: DevelopmentScores({
        'technical': {'firstTouch': 3, 'progressivePassing': null},
      }),
      strengths: 'Protects the ball well.',
      developmentTargets: 'Play forward sooner.',
      coachNotes: 'Reviewed after training.',
      assessmentReason: 'GENERAL_REVIEW',
    );

    final json = draft.toJson();
    expect(json['developmentRatings'], {
      'technical': {'firstTouch': 3, 'progressivePassing': null},
    });
    expect(json, isNot(contains('ratings')));
    expect(json, isNot(contains('overall')));
    expect(json['strengths'], 'Protects the ball well.');
    expect(json['developmentTargets'], 'Play forward sooner.');
  });

  test('parses domain growth without inventing a combined score', () {
    final summary = DevelopmentGrowthSummary.fromJson({
      'sampleSize': 2,
      'latestAssessmentId': 'a2',
      'previousAssessmentId': 'a1',
      'domains': [
        {
          'key': 'technical',
          'label': 'Technical',
          'latestScore': 4.0,
          'previousScore': 3.5,
          'delta': 0.5,
          'comparableIndicatorCount': 2,
          'indicatorDeltas': {'firstTouch': 1},
          'classification': 'IMPROVING',
        },
      ],
    });

    expect(summary.sampleSize, 2);
    expect(summary.domains.single.delta, 0.5);
    expect(summary.domains.single.comparableIndicatorCount, 2);
    expect(summary.domains.single.indicatorDeltas, {'firstTouch': 1});
  });
}
