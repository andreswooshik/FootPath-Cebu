import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/data/repositories/api_player_repository.dart';
import 'package:footpath_cebu/domain/entities/development_assessment.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _frameworkJson() => {
  'version': 1,
  'name': 'FootPath Development Framework',
  'methodology': 'Holistic development.',
  'disclaimer': 'A FootPath framework.',
  'ageTier': 'DEVELOPMENT',
  'position': 'CM',
  'positionGroup': 'MIDFIELD',
  'scale': const [],
  'domains': const [],
};

Map<String, dynamic> _playerJson() => {
  'id': 7,
  'name': 'Ana Player',
  'age': 15,
  'classYear': 'Class of 2028',
  'ageTier': 'DEVELOPMENT',
  'position': 'CM',
  'ratings': <String, int>{},
  'eligibility': 'ELIGIBLE',
  'developmentAssessment': {
    'frameworkVersion': 1,
    'ratings': {
      'technical': {'firstTouch': 4},
    },
    'domainScores': {'technical': 4.0},
    'strengths': 'Scans early.',
    'developmentTargets': 'Receive on the weaker side.',
    'assessedAt': '2026-08-30T08:00:00Z',
  },
};

void main() {
  test(
    'loads the tailored assessment framework from the player endpoint',
    () async {
      late http.Request captured;
      final api = AuthenticatedApiClient(
        identityProvider: () => ApiIdentity(
          uid: 'coach-uid',
          getIdToken: (_) async => 'firebase-token',
        ),
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'framework': _frameworkJson(),
              'latestAssessment': null,
            }),
            200,
          );
        }),
      );

      final form = await ApiPlayerRepository(
        api: api,
      ).fetchDevelopmentAssessmentForm('7');

      expect(captured.method, 'GET');
      expect(captured.url.path, '/api/players/7/assessment/');
      expect(captured.headers['authorization'], 'Bearer firebase-token');
      expect(form.framework.version, 1);
      expect(form.latestAssessment, isNull);
    },
  );

  test('saves the development draft and parses the refreshed player', () async {
    late http.Request captured;
    final api = AuthenticatedApiClient(
      identityProvider: () => ApiIdentity(
        uid: 'coach-uid',
        getIdToken: (_) async => 'firebase-token',
      ),
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(_playerJson()), 200);
      }),
    );
    final draft = DevelopmentAssessmentDraft(
      frameworkVersion: 1,
      ratings: DevelopmentScores({
        'technical': {'firstTouch': 4},
      }),
      strengths: 'Scans early.',
      developmentTargets: 'Receive on the weaker side.',
      coachNotes: 'Positive month.',
      assessmentReason: 'MONTHLY_REVIEW',
    );

    final player = await ApiPlayerRepository(
      api: api,
    ).saveDevelopmentAssessment('7', draft);
    final body = jsonDecode(captured.body) as Map<String, dynamic>;

    expect(captured.method, 'PUT');
    expect(captured.url.path, '/api/players/7/assessment/');
    expect(body['frameworkVersion'], 1);
    expect(body['developmentRatings'], {
      'technical': {'firstTouch': 4},
    });
    expect(body, isNot(contains('ratings')));
    expect(player.developmentAssessment!.domainScores['technical'], 4.0);
    expect(player.developmentAssessment!.strengths, 'Scans early.');
  });
}
