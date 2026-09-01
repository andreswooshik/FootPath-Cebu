class PlayerStatsCatalog {
  const PlayerStatsCatalog({
    required this.version,
    required this.position,
    required this.roleGroup,
    required this.attributes,
  });
  final int version;
  final String position;
  final String roleGroup;
  final List<String> attributes;

  factory PlayerStatsCatalog.fromJson(Map<String, dynamic> json) =>
      PlayerStatsCatalog(
        version: json['version'] as int? ?? 1,
        position: json['position'] as String? ?? '',
        roleGroup: json['roleGroup'] as String? ?? '',
        attributes: (json['attributes'] as List? ?? const [])
            .map((v) => v.toString())
            .toList(growable: false),
      );
}

class PlayerStatsAssessment {
  const PlayerStatsAssessment({
    required this.id,
    required this.position,
    required this.roleGroup,
    required this.catalogVersion,
    required this.scores,
    required this.overall,
    required this.reason,
    required this.coachNotes,
    required this.createdAt,
    this.assessedBy,
  });
  final String id;
  final String position;
  final String roleGroup;
  final int catalogVersion;
  final Map<String, int> scores;
  final int overall;
  final String reason;
  final String coachNotes;
  final DateTime createdAt;
  final String? assessedBy;

  factory PlayerStatsAssessment.fromJson(Map<String, dynamic> json) =>
      PlayerStatsAssessment(
        id: json['id'].toString(),
        position: json['position'] as String? ?? '',
        roleGroup: json['roleGroup'] as String? ?? '',
        catalogVersion: json['catalogVersion'] as int? ?? 1,
        scores: (json['scores'] as Map<String, dynamic>? ?? const {}).map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        ),
        overall: (json['overall'] as num?)?.toInt() ?? 0,
        reason: json['reason'] as String? ?? '',
        coachNotes: json['coachNotes'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        assessedBy: json['assessedBy'] as String?,
      );
}

class PlayerStatsAttributeChange {
  const PlayerStatsAttributeChange({
    required this.previous,
    required this.current,
    required this.delta,
  });
  final int previous;
  final int current;
  final int delta;
  factory PlayerStatsAttributeChange.fromJson(Map<String, dynamic> json) =>
      PlayerStatsAttributeChange(
        previous: (json['previous'] as num).toInt(),
        current: (json['new'] as num).toInt(),
        delta: (json['delta'] as num).toInt(),
      );
}

class PlayerStatsComparison {
  const PlayerStatsComparison({
    required this.baseline,
    this.previousOverall,
    this.newOverall,
    this.overallDelta,
    this.attributes = const {},
  });
  final bool baseline;
  final int? previousOverall;
  final int? newOverall;
  final int? overallDelta;
  final Map<String, PlayerStatsAttributeChange> attributes;
  factory PlayerStatsComparison.fromJson(Map<String, dynamic> json) =>
      PlayerStatsComparison(
        baseline: json['baseline'] as bool? ?? true,
        previousOverall: (json['previousOverall'] as num?)?.toInt(),
        newOverall: (json['newOverall'] as num?)?.toInt(),
        overallDelta: (json['overallDelta'] as num?)?.toInt(),
        attributes: json['attributes'] is Map
            ? Map<String, dynamic>.from(json['attributes'] as Map).map(
                (k, v) => MapEntry(
                  k,
                  PlayerStatsAttributeChange.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              )
            : const {},
      );
}

class PlayerStats {
  const PlayerStats({
    required this.catalog,
    required this.latest,
    required this.comparison,
    required this.history,
    required this.legacyHistory,
  });
  final PlayerStatsCatalog catalog;
  final PlayerStatsAssessment? latest;
  final PlayerStatsComparison comparison;
  final List<PlayerStatsAssessment> history;
  final List<Map<String, dynamic>> legacyHistory;
  factory PlayerStats.fromJson(Map<String, dynamic> json) => PlayerStats(
    catalog: PlayerStatsCatalog.fromJson(
      json['catalog'] as Map<String, dynamic>,
    ),
    latest: json['latestCompatibleStats'] == null
        ? null
        : PlayerStatsAssessment.fromJson(
            json['latestCompatibleStats'] as Map<String, dynamic>,
          ),
    comparison: PlayerStatsComparison.fromJson(
      json['comparison'] as Map<String, dynamic>? ?? const {},
    ),
    history: (json['history'] as List? ?? const [])
        .map((v) => PlayerStatsAssessment.fromJson(v as Map<String, dynamic>))
        .toList(growable: false),
    legacyHistory: (json['legacyStatsHistory'] as List? ?? const [])
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList(growable: false),
  );
}

class PlayerStatsDraft {
  const PlayerStatsDraft({
    required this.catalogVersion,
    required this.scores,
    required this.reason,
    required this.coachNotes,
  });
  final int catalogVersion;
  final Map<String, int> scores;
  final String reason;
  final String coachNotes;
  Map<String, dynamic> toJson() => {
    'catalogVersion': catalogVersion,
    'scores': scores,
    'reason': reason,
    'coachNotes': coachNotes,
  };
}

class PlayerStatsSaveResult {
  const PlayerStatsSaveResult({
    required this.assessment,
    required this.comparison,
  });
  final PlayerStatsAssessment assessment;
  final PlayerStatsComparison comparison;
}
