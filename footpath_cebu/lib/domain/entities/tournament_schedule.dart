import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/tournament_roster.dart';

enum TournamentFixtureStatus { scheduled, postponed, cancelled, completed }

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
  });

  final String id;
  final int maxAge;
  final String label;
  final DateTime? scheduledAt;
  final TournamentSquad? squad;

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

class TournamentSchedule {
  const TournamentSchedule({
    required this.id,
    required this.title,
    required this.venue,
    required this.startsOn,
    required this.isPublished,
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
    documentUrl: documentUrl,
    publishedAt: publishedAt ?? this.publishedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    ageBrackets: ageBrackets ?? this.ageBrackets,
    fixtures: fixtures ?? this.fixtures,
  );

  factory TournamentSchedule.fromJson(Map<String, dynamic> json) =>
      TournamentSchedule(
        id: json['id'].toString(),
        title: json['title'] as String? ?? '',
        venue: json['venue'] as String? ?? '',
        startsOn: DateTime.parse(json['startsOn'] as String),
        isPublished: json['isPublished'] as bool? ?? true,
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

int? _asNullableInt(dynamic value) => switch (value) {
  int number => number,
  num number => number.toInt(),
  String text => int.tryParse(text),
  _ => null,
};
