import 'package:footpath_cebu/domain/entities/football_match.dart';

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

  bool get hasResult =>
      matchId != null || status == TournamentFixtureStatus.completed;

  bool get canRecordResult {
    if (hasResult || status == TournamentFixtureStatus.cancelled) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final kickoffDay = DateTime(kickoffAt.year, kickoffAt.month, kickoffAt.day);
    return !kickoffDay.isAfter(today) && opponent.trim().toUpperCase() != 'TBD';
  }

  factory TournamentFixture.fromJson(Map<String, dynamic> json) =>
      TournamentFixture(
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
      );
}

class TournamentSchedule {
  const TournamentSchedule({
    required this.id,
    required this.title,
    required this.publishedAt,
    required this.updatedAt,
    required this.fixtures,
    this.documentUrl,
  });

  final String id;
  final String title;
  final String? documentUrl;
  final DateTime publishedAt;
  final DateTime updatedAt;
  final List<TournamentFixture> fixtures;

  factory TournamentSchedule.fromJson(Map<String, dynamic> json) =>
      TournamentSchedule(
        id: json['id'].toString(),
        title: json['title'] as String? ?? '',
        documentUrl: json['documentUrl'] as String?,
        publishedAt: DateTime.parse(json['publishedAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        fixtures: (json['fixtures'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(TournamentFixture.fromJson)
            .toList(growable: false),
      );
}
