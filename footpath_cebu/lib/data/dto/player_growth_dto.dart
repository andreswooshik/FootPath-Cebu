import 'package:footpath_cebu/data/dto/player_dto.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/entities/development_assessment.dart';
import 'package:footpath_cebu/domain/entities/match_performance.dart';
import 'package:footpath_cebu/domain/entities/player_growth.dart';

abstract final class AssessmentSnapshotDto {
  static AssessmentSnapshot fromJson(Map<String, dynamic> json) =>
      AssessmentSnapshot(
        id: json['id'].toString(),
        playerId: json['playerId'].toString(),
        position: json['position'] as String? ?? '',
        ratings: PlayerRatingsDto.fromJson(
          json['ratings'] as Map<String, dynamic>? ?? const {},
        ),
        overall: _asInt(json['overall']),
        coachNotes: json['coachNotes'] as String? ?? '',
        reason: AssessmentReasonInfo.fromWire(
          json['assessmentReason'] as String?,
        ),
        createdAt: DateTime.parse(json['createdAt'] as String),
        assessedByRole: json['assessedByRole'] as String?,
      );
}

abstract final class AssessmentGrowthSummaryDto {
  static AssessmentGrowthSummary fromJson(Map<String, dynamic> json) =>
      AssessmentGrowthSummary(
        sampleSize: _asInt(json['sampleSize']),
        latestOverall: _asNullableInt(json['latestOverall']),
        previousOverall: _asNullableInt(json['previousOverall']),
        overallDelta: _asNullableInt(json['overallDelta']),
        attributeDeltas:
            (json['attributeDeltas'] as Map<String, dynamic>? ?? const {}).map(
              (key, value) => MapEntry(key, _asInt(value)),
            ),
        classification: GrowthClassificationInfo.fromWire(
          json['classification'] as String?,
        ),
      );
}

abstract final class TrainingGrowthGroupDto {
  static TrainingGrowthGroup fromJson(Map<String, dynamic> json) {
    final comparison = json['comparison'] as Map<String, dynamic>? ?? const {};
    return TrainingGrowthGroup(
      focus: json['focus'] as String? ?? '',
      sampleSize: _asInt(json['sampleSize']),
      presentCount: _asInt(json['presentCount']),
      attendanceRate: _asDouble(json['attendanceRate']),
      averageEffort: _asDouble(json['averageEffort']),
      averagePerformanceScore: _asDouble(json['averagePerformanceScore']),
      classification: GrowthClassificationInfo.fromWire(
        comparison['classification'] as String?,
      ),
      comparisonMetric: comparison['metric'] as String? ?? 'PERFORMANCE_SCORE',
      recentSampleSize: _asInt(comparison['recentSampleSize']),
      previousSampleSize: _asInt(comparison['previousSampleSize']),
      performanceDelta: _asDouble(comparison['performanceDelta']),
      effortDelta: _asDouble(comparison['effortDelta']),
      history: (json['history'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(Attendance.fromJson)
          .toList(growable: false),
    );
  }
}

abstract final class MatchGrowthDto {
  static MatchGrowth fromJson(Map<String, dynamic> json) => MatchGrowth(
    sampleSize: _asInt(json['sampleSize']),
    summary: MatchPerformanceSummary.fromJson(
      json['summary'] as Map<String, dynamic>? ?? const {},
    ),
    metrics: (json['metrics'] as Map<String, dynamic>? ?? const {}).map(
      (key, value) => MapEntry(
        key,
        MatchMetricGrowthDto.fromJson(value as Map<String, dynamic>),
      ),
    ),
    history: (json['history'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(MatchPerformance.fromJson)
        .toList(growable: false),
  );
}

abstract final class MatchMetricGrowthDto {
  static MatchMetricGrowth fromJson(Map<String, dynamic> json) =>
      MatchMetricGrowth(
        recent: _asDouble(json['recent']),
        previous: _asDouble(json['previous']),
        delta: _asDouble(json['delta']),
        classification: GrowthClassificationInfo.fromWire(
          json['classification'] as String?,
        ),
      );
}

abstract final class TournamentGrowthGroupDto {
  static TournamentGrowthGroup fromJson(Map<String, dynamic> json) {
    final team = json['teamRecord'] as Map<String, dynamic>? ?? const {};
    final history = (json['history'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(MatchPerformance.fromJson)
        .toList(growable: false);
    return TournamentGrowthGroup(
      tournamentId: json['tournamentId'].toString(),
      tournament: json['tournament'] as String? ?? '',
      ageBracketLabel: json['ageBracketLabel'] as String?,
      sampleSize: _asInt(json['sampleSize']),
      summary: MatchPerformanceSummary.fromJson(
        json['summary'] as Map<String, dynamic>? ?? const {},
      ),
      wins: _asInt(team['wins']),
      draws: _asInt(team['draws']),
      losses: _asInt(team['losses']),
      growth: MatchGrowthDto.fromJson(
        json['growth'] as Map<String, dynamic>? ?? const {},
      ),
      history: history,
    );
  }
}

abstract final class PlayerGrowthDto {
  static PlayerGrowth fromJson(Map<String, dynamic> json) {
    final assessment = json['assessments'] as Map<String, dynamic>?;
    final training = json['training'] as Map<String, dynamic>?;
    final tournaments = json['tournaments'] as Map<String, dynamic>?;
    return PlayerGrowth(
      playerId: json['playerId'].toString(),
      playerName: json['playerName'] as String? ?? '',
      position: json['position'] as String? ?? '',
      assessmentSummary: assessment == null
          ? null
          : AssessmentGrowthSummaryDto.fromJson(
              assessment['summary'] as Map<String, dynamic>? ?? const {},
            ),
      assessments: (assessment?['history'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(AssessmentSnapshotDto.fromJson)
          .toList(growable: false),
      assessmentFramework: assessment?['framework'] is Map<String, dynamic>
          ? AssessmentFramework.fromJson(
              assessment!['framework'] as Map<String, dynamic>,
            )
          : null,
      developmentSummary:
          assessment?['developmentSummary'] is Map<String, dynamic>
          ? DevelopmentGrowthSummary.fromJson(
              assessment!['developmentSummary'] as Map<String, dynamic>,
            )
          : null,
      developmentAssessments:
          (assessment?['developmentHistory'] as List? ?? const [])
              .cast<Map<String, dynamic>>()
              .map(DevelopmentAssessmentSnapshot.fromJson)
              .toList(growable: false),
      training: (training?['groups'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(TrainingGrowthGroupDto.fromJson)
          .toList(growable: false),
      regularMatches: json['regularMatches'] is Map<String, dynamic>
          ? MatchGrowthDto.fromJson(
              json['regularMatches'] as Map<String, dynamic>,
            )
          : null,
      tournaments: (tournaments?['groups'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(TournamentGrowthGroupDto.fromJson)
          .toList(growable: false),
    );
  }
}

int _asInt(dynamic value) => switch (value) {
  int number => number,
  num number => number.toInt(),
  String text => int.tryParse(text) ?? 0,
  _ => 0,
};

int? _asNullableInt(dynamic value) => value == null ? null : _asInt(value);

double? _asDouble(dynamic value) => switch (value) {
  num number => number.toDouble(),
  String text => double.tryParse(text),
  _ => null,
};
