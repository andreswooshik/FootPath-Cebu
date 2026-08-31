import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/entities/match_performance.dart';
import 'package:footpath_cebu/domain/entities/player.dart';

enum GrowthRange { last5, last10, last30Days, last90Days, all }

extension GrowthRangeInfo on GrowthRange {
  String get wire => switch (this) {
    GrowthRange.last5 => 'last5',
    GrowthRange.last10 => 'last10',
    GrowthRange.last30Days => 'last30days',
    GrowthRange.last90Days => 'last90days',
    GrowthRange.all => 'all',
  };

  String get label => switch (this) {
    GrowthRange.last5 => 'Last 5',
    GrowthRange.last10 => 'Last 10',
    GrowthRange.last30Days => '30 days',
    GrowthRange.last90Days => '90 days',
    GrowthRange.all => 'All',
  };
}

enum GrowthCategory { all, assessment, training, regularMatch, tournament }

extension GrowthCategoryInfo on GrowthCategory {
  String get wire => switch (this) {
    GrowthCategory.all => 'all',
    GrowthCategory.assessment => 'assessment',
    GrowthCategory.training => 'training',
    GrowthCategory.regularMatch => 'regular_match',
    GrowthCategory.tournament => 'tournament',
  };
}

enum GrowthClassification {
  improving,
  stable,
  needsAttention,
  insufficientData,
}

extension GrowthClassificationInfo on GrowthClassification {
  String get label => switch (this) {
    GrowthClassification.improving => 'Improving',
    GrowthClassification.stable => 'Stable',
    GrowthClassification.needsAttention => 'Needs attention',
    GrowthClassification.insufficientData => 'Insufficient data',
  };

  static GrowthClassification fromWire(String? value) => switch (value) {
    'IMPROVING' => GrowthClassification.improving,
    'STABLE' => GrowthClassification.stable,
    'NEEDS_ATTENTION' => GrowthClassification.needsAttention,
    _ => GrowthClassification.insufficientData,
  };
}

enum AssessmentReason {
  generalReview,
  monthlyReview,
  postTournament,
  returnFromInjury,
  baseline,
  other,
}

extension AssessmentReasonInfo on AssessmentReason {
  String get wire => switch (this) {
    AssessmentReason.generalReview => 'GENERAL_REVIEW',
    AssessmentReason.monthlyReview => 'MONTHLY_REVIEW',
    AssessmentReason.postTournament => 'POST_TOURNAMENT',
    AssessmentReason.returnFromInjury => 'RETURN_FROM_INJURY',
    AssessmentReason.baseline => 'BASELINE',
    AssessmentReason.other => 'OTHER',
  };

  String get label => switch (this) {
    AssessmentReason.generalReview => 'General review',
    AssessmentReason.monthlyReview => 'Monthly review',
    AssessmentReason.postTournament => 'Post-tournament',
    AssessmentReason.returnFromInjury => 'Return from injury',
    AssessmentReason.baseline => 'Baseline',
    AssessmentReason.other => 'Other',
  };

  static AssessmentReason fromWire(String? value) =>
      AssessmentReason.values.firstWhere(
        (reason) => reason.wire == value,
        orElse: () => AssessmentReason.generalReview,
      );
}

class GrowthQuery {
  const GrowthQuery({
    required this.playerId,
    this.range = GrowthRange.last10,
    this.category = GrowthCategory.all,
    this.from,
    this.to,
  });

  final String playerId;
  final GrowthRange range;
  final GrowthCategory category;
  final DateTime? from;
  final DateTime? to;

  @override
  bool operator ==(Object other) =>
      other is GrowthQuery &&
      other.playerId == playerId &&
      other.range == range &&
      other.category == category &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(playerId, range, category, from, to);
}

class AssessmentSnapshot {
  const AssessmentSnapshot({
    required this.id,
    required this.playerId,
    required this.position,
    required this.ratings,
    required this.overall,
    required this.coachNotes,
    required this.reason,
    required this.createdAt,
    this.assessedByRole,
  });

  final String id;
  final String playerId;
  final String position;
  final PlayerRatings ratings;
  final int overall;
  final String coachNotes;
  final AssessmentReason reason;
  final DateTime createdAt;
  final String? assessedByRole;

  factory AssessmentSnapshot.fromJson(Map<String, dynamic> json) =>
      AssessmentSnapshot(
        id: json['id'].toString(),
        playerId: json['playerId'].toString(),
        position: json['position'] as String? ?? '',
        ratings: PlayerRatings.fromJson(
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

class AssessmentGrowthSummary {
  const AssessmentGrowthSummary({
    required this.sampleSize,
    required this.latestOverall,
    required this.previousOverall,
    required this.overallDelta,
    required this.attributeDeltas,
    required this.classification,
  });

  final int sampleSize;
  final int? latestOverall;
  final int? previousOverall;
  final int? overallDelta;
  final Map<String, int> attributeDeltas;
  final GrowthClassification classification;

  factory AssessmentGrowthSummary.fromJson(Map<String, dynamic> json) =>
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

class TrainingGrowthGroup {
  const TrainingGrowthGroup({
    required this.focus,
    required this.sampleSize,
    required this.presentCount,
    required this.attendanceRate,
    required this.averageEffort,
    required this.averagePerformanceScore,
    required this.classification,
    required this.comparisonMetric,
    required this.recentSampleSize,
    required this.previousSampleSize,
    required this.performanceDelta,
    required this.effortDelta,
    required this.history,
  });

  final String focus;
  final int sampleSize;
  final int presentCount;
  final double? attendanceRate;
  final double? averageEffort;
  final double? averagePerformanceScore;
  final GrowthClassification classification;
  final String comparisonMetric;
  final int recentSampleSize;
  final int previousSampleSize;
  final double? performanceDelta;
  final double? effortDelta;
  final List<Attendance> history;

  factory TrainingGrowthGroup.fromJson(Map<String, dynamic> json) {
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

class MatchGrowth {
  const MatchGrowth({
    required this.sampleSize,
    required this.summary,
    required this.metrics,
    required this.history,
  });

  final int sampleSize;
  final MatchPerformanceSummary summary;
  final Map<String, MatchMetricGrowth> metrics;
  final List<MatchPerformance> history;

  factory MatchGrowth.fromJson(Map<String, dynamic> json) => MatchGrowth(
    sampleSize: _asInt(json['sampleSize']),
    summary: MatchPerformanceSummary.fromJson(
      json['summary'] as Map<String, dynamic>? ?? const {},
    ),
    metrics: (json['metrics'] as Map<String, dynamic>? ?? const {}).map(
      (key, value) => MapEntry(
        key,
        MatchMetricGrowth.fromJson(value as Map<String, dynamic>),
      ),
    ),
    history: (json['history'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(MatchPerformance.fromJson)
        .toList(growable: false),
  );
}

class MatchMetricGrowth {
  const MatchMetricGrowth({
    required this.recent,
    required this.previous,
    required this.delta,
    required this.classification,
  });

  final double? recent;
  final double? previous;
  final double? delta;
  final GrowthClassification classification;

  factory MatchMetricGrowth.fromJson(Map<String, dynamic> json) =>
      MatchMetricGrowth(
        recent: _asDouble(json['recent']),
        previous: _asDouble(json['previous']),
        delta: _asDouble(json['delta']),
        classification: GrowthClassificationInfo.fromWire(
          json['classification'] as String?,
        ),
      );
}

class TournamentGrowthGroup {
  const TournamentGrowthGroup({
    required this.tournamentId,
    required this.tournament,
    required this.ageBracketLabel,
    required this.sampleSize,
    required this.summary,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.growth,
    required this.history,
  });

  final String tournamentId;
  final String tournament;
  final String? ageBracketLabel;
  final int sampleSize;
  final MatchPerformanceSummary summary;
  final int wins;
  final int draws;
  final int losses;
  final MatchGrowth growth;
  final List<MatchPerformance> history;

  factory TournamentGrowthGroup.fromJson(Map<String, dynamic> json) {
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
      growth: MatchGrowth.fromJson(
        json['growth'] as Map<String, dynamic>? ?? const {},
      ),
      history: history,
    );
  }
}

class PlayerGrowth {
  const PlayerGrowth({
    required this.playerId,
    required this.playerName,
    required this.position,
    required this.assessmentSummary,
    required this.assessments,
    required this.training,
    required this.regularMatches,
    required this.tournaments,
  });

  final String playerId;
  final String playerName;
  final String position;
  final AssessmentGrowthSummary? assessmentSummary;
  final List<AssessmentSnapshot> assessments;
  final List<TrainingGrowthGroup> training;
  final MatchGrowth? regularMatches;
  final List<TournamentGrowthGroup> tournaments;

  factory PlayerGrowth.fromJson(Map<String, dynamic> json) {
    final assessment = json['assessments'] as Map<String, dynamic>?;
    final training = json['training'] as Map<String, dynamic>?;
    final tournaments = json['tournaments'] as Map<String, dynamic>?;
    return PlayerGrowth(
      playerId: json['playerId'].toString(),
      playerName: json['playerName'] as String? ?? '',
      position: json['position'] as String? ?? '',
      assessmentSummary: assessment == null
          ? null
          : AssessmentGrowthSummary.fromJson(
              assessment['summary'] as Map<String, dynamic>? ?? const {},
            ),
      assessments: (assessment?['history'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(AssessmentSnapshot.fromJson)
          .toList(growable: false),
      training: (training?['groups'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(TrainingGrowthGroup.fromJson)
          .toList(growable: false),
      regularMatches: json['regularMatches'] is Map<String, dynamic>
          ? MatchGrowth.fromJson(json['regularMatches'] as Map<String, dynamic>)
          : null,
      tournaments: (tournaments?['groups'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(TournamentGrowthGroup.fromJson)
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
