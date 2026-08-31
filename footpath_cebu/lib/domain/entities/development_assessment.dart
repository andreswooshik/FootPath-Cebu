/// Typed contracts for the FootPath Development Framework.
class DevelopmentScores {
  DevelopmentScores(Map<String, Map<String, int?>> values)
    : values = {
        for (final entry in values.entries)
          entry.key: Map<String, int?>.unmodifiable(entry.value),
      };

  factory DevelopmentScores.empty(AssessmentFramework framework) =>
      DevelopmentScores({
        for (final domain in framework.domains)
          domain.key: {
            for (final indicator in domain.indicators) indicator.key: null,
          },
      });

  factory DevelopmentScores.fromJson(Map<String, dynamic> json) =>
      DevelopmentScores({
        for (final domain in json.entries)
          domain.key: {
            for (final indicator
                in (domain.value as Map<String, dynamic>? ?? const {}).entries)
              indicator.key: _asNullableInt(indicator.value),
          },
      });

  final Map<String, Map<String, int?>> values;

  int? score(String domainKey, String indicatorKey) =>
      values[domainKey]?[indicatorKey];

  int observedCount(String domainKey) =>
      values[domainKey]?.values.whereType<int>().length ?? 0;

  double? average(String domainKey) {
    final observed = values[domainKey]?.values.whereType<int>().toList() ?? [];
    if (observed.isEmpty) return null;
    return observed.reduce((a, b) => a + b) / observed.length;
  }

  DevelopmentScores withScore(
    String domainKey,
    String indicatorKey,
    int? value,
  ) => DevelopmentScores({
    for (final domain in values.entries)
      domain.key: {
        for (final indicator in domain.value.entries)
          indicator.key:
              domain.key == domainKey && indicator.key == indicatorKey
              ? value
              : indicator.value,
      },
  });

  Map<String, dynamic> toJson() => {
    for (final domain in values.entries)
      domain.key: Map<String, int?>.from(domain.value),
  };
}

class DevelopmentScaleOption {
  const DevelopmentScaleOption({
    required this.value,
    required this.label,
    required this.description,
  });

  final int? value;
  final String label;
  final String description;

  factory DevelopmentScaleOption.fromJson(Map<String, dynamic> json) =>
      DevelopmentScaleOption(
        value: _asNullableInt(json['value']),
        label: json['label'] as String? ?? '',
        description: json['description'] as String? ?? '',
      );
}

class DevelopmentIndicator {
  const DevelopmentIndicator({
    required this.key,
    required this.label,
    required this.description,
    required this.scope,
  });

  final String key;
  final String label;
  final String description;
  final String scope;

  factory DevelopmentIndicator.fromJson(Map<String, dynamic> json) =>
      DevelopmentIndicator(
        key: json['key'] as String? ?? '',
        label: json['label'] as String? ?? '',
        description: json['description'] as String? ?? '',
        scope: json['scope'] as String? ?? 'CORE',
      );
}

class DevelopmentDomain {
  const DevelopmentDomain({
    required this.key,
    required this.label,
    required this.description,
    required this.guidance,
    required this.minimumObserved,
    required this.indicators,
  });

  final String key;
  final String label;
  final String description;
  final String guidance;
  final int minimumObserved;
  final List<DevelopmentIndicator> indicators;

  factory DevelopmentDomain.fromJson(Map<String, dynamic> json) =>
      DevelopmentDomain(
        key: json['key'] as String? ?? '',
        label: json['label'] as String? ?? '',
        description: json['description'] as String? ?? '',
        guidance: json['guidance'] as String? ?? '',
        minimumObserved: _asInt(json['minimumObserved']),
        indicators: (json['indicators'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(DevelopmentIndicator.fromJson)
            .toList(growable: false),
      );
}

class AssessmentFramework {
  const AssessmentFramework({
    required this.version,
    required this.name,
    required this.methodology,
    required this.disclaimer,
    required this.ageTier,
    required this.position,
    required this.positionGroup,
    required this.scale,
    required this.domains,
  });

  final int version;
  final String name;
  final String methodology;
  final String disclaimer;
  final String ageTier;
  final String position;
  final String? positionGroup;
  final List<DevelopmentScaleOption> scale;
  final List<DevelopmentDomain> domains;

  factory AssessmentFramework.fromJson(Map<String, dynamic> json) =>
      AssessmentFramework(
        version: _asInt(json['version']),
        name: json['name'] as String? ?? '',
        methodology: json['methodology'] as String? ?? '',
        disclaimer: json['disclaimer'] as String? ?? '',
        ageTier: json['ageTier'] as String? ?? '',
        position: json['position'] as String? ?? '',
        positionGroup: json['positionGroup'] as String?,
        scale: (json['scale'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(DevelopmentScaleOption.fromJson)
            .toList(growable: false),
        domains: (json['domains'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(DevelopmentDomain.fromJson)
            .toList(growable: false),
      );
}

class CurrentDevelopmentAssessment {
  const CurrentDevelopmentAssessment({
    required this.frameworkVersion,
    required this.ratings,
    required this.domainScores,
    required this.strengths,
    required this.developmentTargets,
    required this.assessedAt,
  });

  final int frameworkVersion;
  final DevelopmentScores ratings;
  final Map<String, double?> domainScores;
  final String strengths;
  final String developmentTargets;
  final DateTime? assessedAt;

  factory CurrentDevelopmentAssessment.fromJson(Map<String, dynamic> json) =>
      CurrentDevelopmentAssessment(
        frameworkVersion: _asInt(json['frameworkVersion']),
        ratings: DevelopmentScores.fromJson(
          json['ratings'] as Map<String, dynamic>? ?? const {},
        ),
        domainScores: _doubleMap(json['domainScores']),
        strengths: json['strengths'] as String? ?? '',
        developmentTargets: json['developmentTargets'] as String? ?? '',
        assessedAt: _asDate(json['assessedAt']),
      );
}

class DevelopmentAssessmentSnapshot {
  const DevelopmentAssessmentSnapshot({
    required this.id,
    required this.playerId,
    required this.position,
    required this.ageTier,
    required this.ageAtAssessment,
    required this.frameworkVersion,
    required this.ratings,
    required this.domainScores,
    required this.strengths,
    required this.developmentTargets,
    required this.coachNotes,
    required this.assessmentReason,
    required this.createdAt,
    this.assessedByRole,
  });

  final String id;
  final String playerId;
  final String position;
  final String ageTier;
  final int ageAtAssessment;
  final int frameworkVersion;
  final DevelopmentScores ratings;
  final Map<String, double?> domainScores;
  final String strengths;
  final String developmentTargets;
  final String coachNotes;
  final String assessmentReason;
  final DateTime createdAt;
  final String? assessedByRole;

  factory DevelopmentAssessmentSnapshot.fromJson(Map<String, dynamic> json) =>
      DevelopmentAssessmentSnapshot(
        id: json['id'].toString(),
        playerId: json['playerId'].toString(),
        position: json['position'] as String? ?? '',
        ageTier: json['ageTier'] as String? ?? '',
        ageAtAssessment: _asInt(json['ageAtAssessment']),
        frameworkVersion: _asInt(json['frameworkVersion']),
        ratings: DevelopmentScores.fromJson(
          json['ratings'] as Map<String, dynamic>? ?? const {},
        ),
        domainScores: _doubleMap(json['domainScores']),
        strengths: json['strengths'] as String? ?? '',
        developmentTargets: json['developmentTargets'] as String? ?? '',
        coachNotes: json['coachNotes'] as String? ?? '',
        assessmentReason: json['assessmentReason'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
        assessedByRole: json['assessedByRole'] as String?,
      );
}

class DevelopmentAssessmentFormData {
  const DevelopmentAssessmentFormData({
    required this.framework,
    required this.latestAssessment,
  });

  final AssessmentFramework framework;
  final DevelopmentAssessmentSnapshot? latestAssessment;

  factory DevelopmentAssessmentFormData.fromJson(Map<String, dynamic> json) =>
      DevelopmentAssessmentFormData(
        framework: AssessmentFramework.fromJson(
          json['framework'] as Map<String, dynamic>? ?? const {},
        ),
        latestAssessment: json['latestAssessment'] is Map<String, dynamic>
            ? DevelopmentAssessmentSnapshot.fromJson(
                json['latestAssessment'] as Map<String, dynamic>,
              )
            : null,
      );
}

class DevelopmentAssessmentDraft {
  const DevelopmentAssessmentDraft({
    required this.frameworkVersion,
    required this.ratings,
    required this.strengths,
    required this.developmentTargets,
    required this.coachNotes,
    required this.assessmentReason,
  });

  final int frameworkVersion;
  final DevelopmentScores ratings;
  final String strengths;
  final String developmentTargets;
  final String coachNotes;
  final String assessmentReason;

  Map<String, dynamic> toJson() => {
    'frameworkVersion': frameworkVersion,
    'developmentRatings': ratings.toJson(),
    'strengths': strengths,
    'developmentTargets': developmentTargets,
    'coachNotes': coachNotes,
    'assessmentReason': assessmentReason,
  };
}

class DevelopmentDomainTrend {
  const DevelopmentDomainTrend({
    required this.key,
    required this.label,
    required this.latestScore,
    required this.previousScore,
    required this.delta,
    required this.comparableIndicatorCount,
    required this.indicatorDeltas,
    required this.classification,
  });

  final String key;
  final String label;
  final double? latestScore;
  final double? previousScore;
  final double? delta;
  final int comparableIndicatorCount;
  final Map<String, int> indicatorDeltas;
  final String classification;

  factory DevelopmentDomainTrend.fromJson(Map<String, dynamic> json) =>
      DevelopmentDomainTrend(
        key: json['key'] as String? ?? '',
        label: json['label'] as String? ?? '',
        latestScore: _asDouble(json['latestScore']),
        previousScore: _asDouble(json['previousScore']),
        delta: _asDouble(json['delta']),
        comparableIndicatorCount: _asInt(json['comparableIndicatorCount']),
        indicatorDeltas: _intMap(json['indicatorDeltas']),
        classification:
            json['classification'] as String? ?? 'INSUFFICIENT_DATA',
      );
}

class DevelopmentGrowthSummary {
  const DevelopmentGrowthSummary({
    required this.sampleSize,
    required this.latestAssessmentId,
    required this.previousAssessmentId,
    required this.domains,
  });

  final int sampleSize;
  final String? latestAssessmentId;
  final String? previousAssessmentId;
  final List<DevelopmentDomainTrend> domains;

  factory DevelopmentGrowthSummary.fromJson(Map<String, dynamic> json) =>
      DevelopmentGrowthSummary(
        sampleSize: _asInt(json['sampleSize']),
        latestAssessmentId: json['latestAssessmentId']?.toString(),
        previousAssessmentId: json['previousAssessmentId']?.toString(),
        domains: (json['domains'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(DevelopmentDomainTrend.fromJson)
            .toList(growable: false),
      );
}

Map<String, double?> _doubleMap(dynamic value) => (value as Map? ?? const {})
    .map((key, value) => MapEntry(key.toString(), _asDouble(value)));

Map<String, int> _intMap(dynamic value) => (value as Map? ?? const {}).map(
  (key, value) => MapEntry(key.toString(), _asInt(value)),
);

DateTime? _asDate(dynamic value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;

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
