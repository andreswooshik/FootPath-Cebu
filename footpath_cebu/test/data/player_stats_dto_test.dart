import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/data/dto/player_stats_dto.dart';

void main() {
  for (final invalid in [null, '', 'invalid-date', 123]) {
    test('assessment rejects invalid required timestamp: $invalid', () {
      expect(
        () =>
            PlayerStatsAssessmentDto.fromJson({'id': 1, 'createdAt': invalid}),
        throwsFormatException,
      );
      expect(
        () => CurrentPlayerStatsDto.fromJson({'assessedAt': invalid}),
        throwsFormatException,
      );
    });
  }

  test(
    'assessment round-trip preserves timestamp and API compatibility fields',
    () {
      final assessment = PlayerStatsAssessmentDto.fromJson({
        'id': 7,
        'createdAt': '2026-09-01T08:30:00Z',
        'assessmentReason': 'MONTHLY_REVIEW',
        'scores': {'pace': 81},
      });
      final decoded = PlayerStatsAssessmentDto.fromJson(assessment.toJson());
      expect(decoded.id, '7');
      expect(decoded.createdAt, DateTime.utc(2026, 9, 1, 8, 30));
      expect(decoded.reason, 'MONTHLY_REVIEW');
      expect(decoded.scores, {'pace': 81});
    },
  );
}
