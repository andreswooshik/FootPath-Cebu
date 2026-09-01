import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/tournament_roster.dart';

enum TournamentFixtureStatus { scheduled, postponed, cancelled, completed }

enum TournamentLifecycleStatus { draft, published, inProgress, completed }

extension TournamentLifecycleStatusInfo on TournamentLifecycleStatus {
  String get label => switch (this) {
    TournamentLifecycleStatus.draft => 'Draft',
    TournamentLifecycleStatus.published => 'Published',
    TournamentLifecycleStatus.inProgress => 'In Progress',
    TournamentLifecycleStatus.completed => 'Completed',
  };

  static TournamentLifecycleStatus fromWire(
    String? value, {
    required bool isPublished,
  }) => switch (value?.toUpperCase()) {
    'DRAFT' => TournamentLifecycleStatus.draft,
    'IN_PROGRESS' => TournamentLifecycleStatus.inProgress,
    'COMPLETED' => TournamentLifecycleStatus.completed,
    'PUBLISHED' => TournamentLifecycleStatus.published,
    _ =>
      isPublished
          ? TournamentLifecycleStatus.published
          : TournamentLifecycleStatus.draft,
  };
}

extension TournamentFixtureStatusInfo on TournamentFixtureStatus {
  String get label => switch (this) {
    TournamentFixtureStatus.scheduled => 'Scheduled',
    TournamentFixtureStatus.postponed => 'Postponed',
    TournamentFixtureStatus.cancelled => 'Cancelled',
    TournamentFixtureStatus.completed => 'Completed',
  };

  static TournamentFixtureStatus fromWire(String? value) =>
      switch (value?.toUpperCase()) {
        'POSTPONED' => TournamentFixtureStatus.postponed,
        'CANCELLED' => TournamentFixtureStatus.cancelled,
        'COMPLETED' => TournamentFixtureStatus.completed,
        _ => TournamentFixtureStatus.scheduled,
      };
}

class TournamentAgeBracket {
  const TournamentAgeBracket({
    required this.id,
    required this.maxAge,
    required this.label,
    this.scheduledAt,
    this.squad,
    this.academyTiers = const {},
  });

  final String id;
  final int maxAge;
  final String label;
  final DateTime? scheduledAt;
  final TournamentSquad? squad;
  final Set<AgeTier> academyTiers;

  factory TournamentAgeBracket.fromJson(Map<String, dynamic> json) =>
      TournamentAgeBracket(
        id: json['id'].toString(),
        maxAge: json['maxAge'] as int,
        label: json['label'] as String? ?? 'U${json['maxAge']}',
        scheduledAt: json['scheduledAt'] == null
            ? null
            : DateTime.parse(json['scheduledAt'] as String),
        squad: json['squad'] == null
            ? null
            : TournamentSquad.fromJson(json['squad'] as Map<String, dynamic>),
        academyTiers: (json['academyTiers'] as List? ?? const [])
            .map((value) => AgeTierInfo.fromWire(value.toString()))
            .toSet(),
      );
}

class TournamentFixture {
  const TournamentFixture({
    required this.id,
    required this.scheduleId,
    required this.tournament,
    required this.stage,
    required this.opponent,
    required this.kickoffAt,
    this.endsAt,
    required this.venue,
    required this.location,
    required this.status,
    this.matchId,
    this.ageBracketId,
    this.ageBracketLabel,
    this.ourScore,
    this.opponentScore,
    this.outcome,
    this.linkedMatch,
  });

  final String id;
  final String scheduleId;
  final String tournament;
  final String stage;
  final String opponent;
  final DateTime kickoffAt;
  final DateTime? endsAt;

  DateTime get effectiveEndsAt =>
      endsAt ?? kickoffAt.add(const Duration(hours: 2));
  final MatchVenue venue;
  final String location;
  final TournamentFixtureStatus status;
  final String? matchId;
  final String? ageBracketId;
  final String? ageBracketLabel;
  final int? ourScore;
  final int? opponentScore;
  final String? outcome;
  final FootballMatch? linkedMatch;

  bool get hasResult =>
      matchId != null || status == TournamentFixtureStatus.completed;

  bool get canRecordResult {
    if (hasResult || status == TournamentFixtureStatus.cancelled) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final kickoffDay = DateTime(kickoffAt.year, kickoffAt.month, kickoffAt.day);
    return !kickoffDay.isAfter(today) && opponent.trim().toUpperCase() != 'TBD';
  }

  factory TournamentFixture.fromJson(Map<String, dynamic> json) {
    final result = json['result'] as Map<String, dynamic>?;
    return TournamentFixture(
      id: json['id'].toString(),
      scheduleId: json['scheduleId'].toString(),
      tournament: json['tournament'] as String? ?? '',
      stage: json['stage'] as String? ?? '',
      opponent: json['opponent'] as String? ?? 'TBD',
      kickoffAt: DateTime.parse(json['kickoffAt'] as String),
      endsAt: json['endsAt'] == null
          ? null
          : DateTime.parse(json['endsAt'] as String),
      venue: MatchVenueInfo.fromWire(json['venue'] as String?),
      location: json['location'] as String? ?? '',
      status: TournamentFixtureStatusInfo.fromWire(json['status'] as String?),
      matchId: json['matchId']?.toString(),
      ageBracketId: json['ageBracketId']?.toString(),
      ageBracketLabel: json['ageBracketLabel'] as String?,
      ourScore: _asNullableInt(result?['ourScore']),
      opponentScore: _asNullableInt(result?['opponentScore']),
      outcome: result?['outcome'] as String?,
      linkedMatch: result?['match'] is Map<String, dynamic>
          ? FootballMatch.fromJson(result!['match'] as Map<String, dynamic>)
          : null,
    );
  }
}

class TournamentDocumentUpload {
  const TournamentDocumentUpload({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });

  final List<int> bytes;
  final String filename;
  final String contentType;
}

class TournamentFixtureDraft {
  const TournamentFixtureDraft({
    required this.ageBracketId,
    required this.stage,
    required this.opponent,
    required this.kickoffAt,
    this.endsAt,
    required this.venue,
    required this.location,
    required this.status,
  });

  final String ageBracketId;
  final String stage;
  final String opponent;
  final DateTime kickoffAt;
  final DateTime? endsAt;
  final MatchVenue venue;
  final String location;
  final TournamentFixtureStatus status;

  Map<String, dynamic> toJson() => {
    'ageBracketId': int.tryParse(ageBracketId) ?? ageBracketId,
    'stage': stage.trim(),
    'opponent': opponent.trim().isEmpty ? 'TBD' : opponent.trim(),
    'kickoffAt': kickoffAt.toUtc().toIso8601String(),
    'endsAt': (endsAt ?? kickoffAt.add(const Duration(hours: 2)))
        .toUtc()
        .toIso8601String(),
    'venue': venue.name.toUpperCase(),
    'location': location.trim(),
    'status': status.name.toUpperCase(),
  };

  factory TournamentFixtureDraft.fromFixture(TournamentFixture value) =>
      TournamentFixtureDraft(
        ageBracketId: value.ageBracketId ?? '',
        stage: value.stage,
        opponent: value.opponent,
        kickoffAt: value.kickoffAt,
        endsAt: value.endsAt,
        venue: value.venue,
        location: value.location,
        status: value.status,
      );
}

class TournamentParticipantStatisticsDraft {
  const TournamentParticipantStatisticsDraft({
    required this.playerId,
    required this.position,
    this.starter = false,
    this.minutesPlayed = 0,
    this.goals = 0,
    this.assists = 0,
    this.shots = 0,
    this.shotsOnTarget = 0,
    this.passesAttempted = 0,
    this.passesCompleted = 0,
    this.tackles = 0,
    this.interceptions = 0,
    this.yellowCards = 0,
    this.redCards = 0,
    this.saves = 0,
    this.goalsConceded = 0,
    this.cleanSheet = false,
  });

  final String playerId;
  final String position;
  final bool starter;
  final int minutesPlayed;
  final int goals;
  final int assists;
  final int shots;
  final int shotsOnTarget;
  final int passesAttempted;
  final int passesCompleted;
  final int tackles;
  final int interceptions;
  final int yellowCards;
  final int redCards;
  final int saves;
  final int goalsConceded;
  final bool cleanSheet;

  Map<String, dynamic> toJson() => {
    'playerId': int.tryParse(playerId) ?? playerId,
    'statistics': {
      'position': position.trim().toUpperCase(),
      'starter': starter,
      'minutesPlayed': minutesPlayed,
      'goals': goals,
      'assists': assists,
      'shots': shots,
      'shotsOnTarget': shotsOnTarget,
      'passesAttempted': passesAttempted,
      'passesCompleted': passesCompleted,
      'tackles': tackles,
      'interceptions': interceptions,
      'yellowCards': yellowCards,
      'redCards': redCards,
      'saves': saves,
      'goalsConceded': goalsConceded,
      'cleanSheet': cleanSheet,
    },
  };
}

class TournamentResultDraft {
  const TournamentResultDraft({
    required this.ourScore,
    required this.opponentScore,
    required this.participants,
  });

  final int ourScore;
  final int opponentScore;
  final List<TournamentParticipantStatisticsDraft> participants;

  Map<String, dynamic> toJson() => {
    'ourScore': ourScore,
    'opponentScore': opponentScore,
    'participants': participants.map((row) => row.toJson()).toList(),
  };
}

class TournamentSchedule {
  const TournamentSchedule({
    required this.id,
    required this.title,
    required this.venue,
    required this.startsOn,
    required this.isPublished,
    required this.lifecycleStatus,
    required this.hasDocument,
    required this.publishedAt,
    required this.updatedAt,
    required this.ageBrackets,
    required this.fixtures,
    this.documentUrl,
  });

  final String id;
  final String title;
  final String venue;
  final DateTime startsOn;
  final bool isPublished;
  final TournamentLifecycleStatus lifecycleStatus;
  final bool hasDocument;
  final String? documentUrl;
  final DateTime? publishedAt;
  final DateTime updatedAt;
  final List<TournamentAgeBracket> ageBrackets;
  final List<TournamentFixture> fixtures;

  TournamentSchedule copyWith({
    String? title,
    String? venue,
    DateTime? startsOn,
    bool? isPublished,
    TournamentLifecycleStatus? lifecycleStatus,
    bool? hasDocument,
    String? documentUrl,
    bool clearDocumentUrl = false,
    DateTime? publishedAt,
    DateTime? updatedAt,
    List<TournamentAgeBracket>? ageBrackets,
    List<TournamentFixture>? fixtures,
  }) => TournamentSchedule(
    id: id,
    title: title ?? this.title,
    venue: venue ?? this.venue,
    startsOn: startsOn ?? this.startsOn,
    isPublished: isPublished ?? this.isPublished,
    lifecycleStatus: lifecycleStatus ?? this.lifecycleStatus,
    hasDocument: hasDocument ?? this.hasDocument,
    documentUrl: clearDocumentUrl ? null : documentUrl ?? this.documentUrl,
    publishedAt: publishedAt ?? this.publishedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    ageBrackets: ageBrackets ?? this.ageBrackets,
    fixtures: fixtures ?? this.fixtures,
  );

  factory TournamentSchedule.fromJson(Map<String, dynamic> json) {
    final isPublished = json['isPublished'] as bool? ?? false;
    return TournamentSchedule(
      id: json['id'].toString(),
      title: json['title'] as String? ?? '',
      venue: json['venue'] as String? ?? '',
      startsOn: DateTime.parse(json['startsOn'] as String),
      isPublished: isPublished,
      lifecycleStatus: TournamentLifecycleStatusInfo.fromWire(
        json['lifecycleStatus'] as String?,
        isPublished: isPublished,
      ),
      hasDocument:
          json['hasDocument'] as bool? ??
          (json['documentUrl'] as String?)?.isNotEmpty == true,
      documentUrl: json['documentUrl'] as String?,
      publishedAt: json['publishedAt'] == null
          ? null
          : DateTime.parse(json['publishedAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      ageBrackets: (json['ageBrackets'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(TournamentAgeBracket.fromJson)
          .toList(growable: false),
      fixtures: (json['fixtures'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(TournamentFixture.fromJson)
          .toList(growable: false),
    );
  }
}

int? _asNullableInt(dynamic value) => switch (value) {
  int number => number,
  num number => number.toInt(),
  String text => int.tryParse(text),
  _ => null,
};
