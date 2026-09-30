import 'package:footpath_cebu/domain/entities/player_stats.dart';

abstract final class PlayerStatsCatalogDto {
  static PlayerStatsCatalog fromJson(Map<String, dynamic> json) =>
      PlayerStatsCatalog(
        version: json['version'] as int? ?? 1,
        position: json['position'] as String? ?? '',
        roleGroup: json['roleGroup'] as String? ?? '',
        attributes: (json['attributes'] as List? ?? const [])
            .map((v) => v.toString())
            .toList(growable: false),
      );
}

abstract final class CurrentPlayerStatsDto {
  static CurrentPlayerStats fromJson(Map<String, dynamic> json) =>
      CurrentPlayerStats(
        catalogVersion: json['catalogVersion'] as int? ?? 1,
        position: json['position'] as String? ?? '',
        roleGroup: json['roleGroup'] as String? ?? '',
        attributes: (json['attributes'] as List? ?? const [])
            .map((value) => value.toString())
            .toList(growable: false),
        scores: (json['scores'] as Map<String, dynamic>? ?? const {}).map(
          (key, value) => MapEntry(key, (value as num).toInt()),
        ),
        overall: (json['overall'] as num?)?.toInt() ?? 0,
        assessedAt: _requiredDate(json, 'assessedAt'),
      );
}

abstract final class PlayerStatsAssessmentDto {
  static PlayerStatsAssessment fromJson(Map<String, dynamic> json) =>
      PlayerStatsAssessment(
        id: json['id'].toString(),
        position: json['position'] as String? ?? '',
        roleGroup: json['roleGroup'] as String? ?? '',
        catalogVersion: json['catalogVersion'] as int? ?? 1,
        scores: (json['scores'] as Map<String, dynamic>? ?? const {}).map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        ),
        overall: (json['overall'] as num?)?.toInt() ?? 0,
        reason:
            json['reason'] as String? ??
            json['assessmentReason'] as String? ??
            '',
        coachNotes: json['coachNotes'] as String? ?? '',
        createdAt: _requiredDate(json, 'createdAt'),
        assessedBy: json['assessedBy'] as String?,
      );
}

abstract final class LatestPlayerStatsDto {
  static LatestPlayerStats fromJson(Map<String, dynamic> json) =>
      LatestPlayerStats(
        catalog: PlayerStatsCatalogDto.fromJson(
          Map<String, dynamic>.from(json['catalog'] as Map),
        ),
        assessment: PlayerStatsAssessmentDto.fromJson(
          Map<String, dynamic>.from(json['assessment'] as Map),
        ),
      );
}

abstract final class LegacyPlayerStatsAssessmentDto {
  static LegacyPlayerStatsAssessment fromJson(Map<String, dynamic> json) =>
      LegacyPlayerStatsAssessment(
        id: json['id'].toString(),
        position: json['position'] as String? ?? '',
        ratings: (json['ratings'] as Map<String, dynamic>? ?? const {}).map(
          (key, value) => MapEntry(key, (value as num).toInt()),
        ),
        overall: (json['overall'] as num?)?.toInt() ?? 0,
        reason:
            json['reason'] as String? ??
            json['assessmentReason'] as String? ??
            '',
        coachNotes: json['coachNotes'] as String? ?? '',
        createdAt: _requiredDate(json, 'createdAt'),
        assessedByRole: json['assessedByRole'] as String?,
        assessedBy: json['assessedBy'] as String?,
      );
}

abstract final class PlayerStatsAttributeChangeDto {
  static PlayerStatsAttributeChange fromJson(Map<String, dynamic> json) =>
      PlayerStatsAttributeChange(
        previous: (json['previous'] as num).toInt(),
        current: (json['new'] as num).toInt(),
        delta: (json['delta'] as num).toInt(),
      );
}

abstract final class PlayerStatsComparisonDto {
  static PlayerStatsComparison fromJson(Map<String, dynamic> json) =>
      PlayerStatsComparison(
        baseline: json['baseline'] as bool? ?? true,
        previousOverall: (json['previousOverall'] as num?)?.toInt(),
        newOverall: (json['newOverall'] as num?)?.toInt(),
        overallDelta: (json['overallDelta'] as num?)?.toInt(),
        attributes: json['attributes'] is Map
            ? Map<String, dynamic>.from(json['attributes'] as Map).map(
                (k, v) => MapEntry(
                  k,
                  PlayerStatsAttributeChangeDto.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                ),
              )
            : const {},
      );
}

abstract final class PlayerStatsDto {
  static PlayerStats fromJson(Map<String, dynamic> json) => PlayerStats(
    catalog: PlayerStatsCatalogDto.fromJson(
      json['catalog'] as Map<String, dynamic>,
    ),
    latest: json['latestCompatibleStats'] == null
        ? null
        : PlayerStatsAssessmentDto.fromJson(
            json['latestCompatibleStats'] as Map<String, dynamic>,
          ),
    comparison: PlayerStatsComparisonDto.fromJson(
      json['comparison'] as Map<String, dynamic>? ?? const {},
    ),
    history: (json['history'] as List? ?? const [])
        .map(
          (v) => PlayerStatsAssessmentDto.fromJson(v as Map<String, dynamic>),
        )
        .toList(growable: false),
    legacyHistory: (json['legacyStatsHistory'] as List? ?? const [])
        .map(
          (value) => LegacyPlayerStatsAssessmentDto.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        )
        .toList(growable: false),
  );
}

extension PlayerStatsCatalogJson on PlayerStatsCatalog {
  Map<String, dynamic> toJson() => {
    'version': version,
    'position': position,
    'roleGroup': roleGroup,
    'attributes': attributes,
  };
}

extension CurrentPlayerStatsJson on CurrentPlayerStats {
  Map<String, dynamic> toJson() => {
    'catalogVersion': catalogVersion,
    'position': position,
    'roleGroup': roleGroup,
    'attributes': attributes,
    'scores': scores,
    'overall': overall,
    'assessedAt': assessedAt.toIso8601String(),
  };
}

extension PlayerStatsAssessmentJson on PlayerStatsAssessment {
  Map<String, dynamic> toJson() => {
    'id': id,
    'position': position,
    'roleGroup': roleGroup,
    'catalogVersion': catalogVersion,
    'scores': scores,
    'overall': overall,
    'reason': reason,
    'coachNotes': coachNotes,
    'createdAt': createdAt.toIso8601String(),
    'assessedBy': assessedBy,
  };
}

extension LatestPlayerStatsJson on LatestPlayerStats {
  Map<String, dynamic> toJson() => {
    'catalog': catalog.toJson(),
    'assessment': assessment.toJson(),
  };
}

extension PlayerStatsDraftJson on PlayerStatsDraft {
  Map<String, dynamic> toJson() => {
    'catalogVersion': catalogVersion,
    'scores': scores,
    'reason': reason,
    'coachNotes': coachNotes,
  };
}

DateTime _requiredDate(Map<String, dynamic> json, String field) {
  final raw = json[field];
  final date = raw is String ? DateTime.tryParse(raw) : null;
  if (date == null) throw FormatException('Missing or invalid $field');
  return date;
}
