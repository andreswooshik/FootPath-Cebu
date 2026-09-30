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
}

class CurrentPlayerStats {
  const CurrentPlayerStats({
    required this.catalogVersion,
    required this.position,
    required this.roleGroup,
    required this.attributes,
    required this.scores,
    required this.overall,
    required this.assessedAt,
  });

  final int catalogVersion;
  final String position;
  final String roleGroup;
  final List<String> attributes;
  final Map<String, int> scores;
  final int overall;
  final DateTime assessedAt;

  factory CurrentPlayerStats.fromPlayerStats(PlayerStats stats) {
    final latest = stats.latest!;
    return CurrentPlayerStats(
      catalogVersion: latest.catalogVersion,
      position: latest.position,
      roleGroup: latest.roleGroup,
      attributes: stats.catalog.attributes,
      scores: latest.scores,
      overall: latest.overall,
      assessedAt: latest.createdAt,
    );
  }
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
}

/// The latest assessment that is compatible with the player's current
/// position group. Kept on roster payloads so cards never fall back to stale
/// legacy profile ratings.
class LatestPlayerStats {
  const LatestPlayerStats({required this.catalog, required this.assessment});

  final PlayerStatsCatalog catalog;
  final PlayerStatsAssessment assessment;
}

extension CurrentPlayerStatsCompatibility on CurrentPlayerStats {
  LatestPlayerStats get asLatestPlayerStats => LatestPlayerStats(
    catalog: PlayerStatsCatalog(
      version: catalogVersion,
      position: position,
      roleGroup: roleGroup,
      attributes: attributes,
    ),
    assessment: PlayerStatsAssessment(
      id: 'current',
      position: position,
      roleGroup: roleGroup,
      catalogVersion: catalogVersion,
      scores: scores,
      overall: overall,
      reason: '',
      coachNotes: '',
      createdAt: assessedAt,
    ),
  );
}

class LegacyPlayerStatsAssessment {
  const LegacyPlayerStatsAssessment({
    required this.id,
    required this.position,
    required this.ratings,
    required this.overall,
    required this.reason,
    required this.coachNotes,
    required this.createdAt,
    this.assessedByRole,
    this.assessedBy,
  });

  final String id;
  final String position;
  final Map<String, int> ratings;
  final int overall;
  final String reason;
  final String coachNotes;
  final DateTime createdAt;
  final String? assessedByRole;
  final String? assessedBy;
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
  final List<LegacyPlayerStatsAssessment> legacyHistory;
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
}

class PlayerStatsSaveResult {
  const PlayerStatsSaveResult({
    required this.assessment,
    required this.comparison,
  });
  final PlayerStatsAssessment assessment;
  final PlayerStatsComparison comparison;
}
