enum TournamentSquadStatus { draft, published }

extension TournamentSquadStatusInfo on TournamentSquadStatus {
  String get label => switch (this) {
    TournamentSquadStatus.draft => 'Draft',
    TournamentSquadStatus.published => 'Published',
  };

  static TournamentSquadStatus fromWire(String? value) =>
      value?.toUpperCase() == 'PUBLISHED'
      ? TournamentSquadStatus.published
      : TournamentSquadStatus.draft;
}

class TournamentSquadEntry {
  const TournamentSquadEntry({
    required this.id,
    required this.playerId,
    required this.playerName,
    required this.tournamentPosition,
    this.availability,
    this.availabilityReason,
  });

  final String id;
  final String playerId;
  final String playerName;
  final String tournamentPosition;
  final String? availability;
  final String? availabilityReason;

  bool get isUnavailable => availability == 'BLOCKED';

  factory TournamentSquadEntry.fromJson(Map<String, dynamic> json) =>
      TournamentSquadEntry(
        id: json['id'].toString(),
        playerId: json['playerId'].toString(),
        playerName: json['playerName'] as String? ?? '',
        tournamentPosition: json['tournamentPosition'] as String? ?? '',
        availability: json['availability'] as String?,
        availabilityReason: json['availabilityReason'] as String?,
      );
}

class TournamentSquad {
  const TournamentSquad({
    required this.id,
    required this.bracketId,
    required this.status,
    required this.entries,
    this.publishedAt,
  });

  final String? id;
  final String bracketId;
  final TournamentSquadStatus status;
  final DateTime? publishedAt;
  final List<TournamentSquadEntry> entries;

  factory TournamentSquad.fromJson(Map<String, dynamic> json) =>
      TournamentSquad(
        id: json['id']?.toString(),
        bracketId: json['bracketId'].toString(),
        status: TournamentSquadStatusInfo.fromWire(json['status'] as String?),
        publishedAt: json['publishedAt'] == null
            ? null
            : DateTime.parse(json['publishedAt'] as String),
        entries: (json['entries'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(TournamentSquadEntry.fromJson)
            .toList(growable: false),
      );
}

enum TournamentCandidateEligibility { eligible, warning, blocked }

extension TournamentCandidateEligibilityInfo on TournamentCandidateEligibility {
  static TournamentCandidateEligibility fromWire(String? value) =>
      switch (value?.toUpperCase()) {
        'WARNING' => TournamentCandidateEligibility.warning,
        'BLOCKED' => TournamentCandidateEligibility.blocked,
        _ => TournamentCandidateEligibility.eligible,
      };
}

class TournamentRosterCandidate {
  const TournamentRosterCandidate({
    required this.playerId,
    required this.playerName,
    required this.currentPosition,
    required this.eligibility,
    required this.eligibilityCode,
    required this.eligibilityReason,
    required this.selected,
    required this.tournamentPosition,
  });

  final String playerId;
  final String playerName;
  final String currentPosition;
  final TournamentCandidateEligibility eligibility;
  final String eligibilityCode;
  final String eligibilityReason;
  final bool selected;
  final String tournamentPosition;

  factory TournamentRosterCandidate.fromJson(Map<String, dynamic> json) =>
      TournamentRosterCandidate(
        playerId: json['playerId'].toString(),
        playerName: json['playerName'] as String? ?? '',
        currentPosition: json['currentPosition'] as String? ?? '',
        eligibility: TournamentCandidateEligibilityInfo.fromWire(
          json['eligibility'] as String?,
        ),
        eligibilityCode: json['eligibilityCode'] as String? ?? '',
        eligibilityReason: json['eligibilityReason'] as String? ?? '',
        selected: json['selected'] as bool? ?? false,
        tournamentPosition: json['tournamentPosition'] as String? ?? '',
      );
}

class TournamentRosterSelection {
  const TournamentRosterSelection({required this.playerId, this.position = ''});

  final String playerId;
  final String position;

  Map<String, dynamic> toJson() => {
    'playerId': int.tryParse(playerId) ?? playerId,
    'position': position,
  };
}
