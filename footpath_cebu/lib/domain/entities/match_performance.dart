import 'package:footpath_cebu/domain/entities/football_match.dart';

enum MatchRatingStatus { awaitingStatistics, awaitingRating, rated }

extension MatchRatingStatusWire on MatchRatingStatus {
  String get label => switch (this) {
    MatchRatingStatus.awaitingStatistics => 'Awaiting Coordinator statistics',
    MatchRatingStatus.awaitingRating => 'Awaiting Coach rating',
    MatchRatingStatus.rated => 'Rated',
  };

  static MatchRatingStatus fromWire(String? value) => switch (value) {
    'RATED' => MatchRatingStatus.rated,
    'AWAITING_RATING' => MatchRatingStatus.awaitingRating,
    _ => MatchRatingStatus.awaitingStatistics,
  };
}

/// One historical player's objective statistics and optional Coach rating.
class MatchPerformance {
  const MatchPerformance({
    required this.id,
    required this.playerId,
    required this.playerName,
    required this.match,
    required this.position,
    required this.starter,
    required this.minutesPlayed,
    required this.goals,
    required this.assists,
    required this.shots,
    required this.shotsOnTarget,
    required this.passesAttempted,
    required this.passesCompleted,
    required this.tackles,
    required this.interceptions,
    required this.yellowCards,
    required this.redCards,
    required this.saves,
    required this.goalsConceded,
    required this.cleanSheet,
    required this.coachRating,
    required this.notes,
    required this.ratingStatus,
  });

  final String id;
  final String playerId;
  final String playerName;
  final FootballMatch match;
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
  final double? coachRating;
  final String notes;
  final MatchRatingStatus ratingStatus;

  double? get passCompletionRate =>
      passesAttempted == 0 ? null : passesCompleted * 100 / passesAttempted;

  factory MatchPerformance.fromJson(Map<String, dynamic> json) =>
      MatchPerformance(
        id: json['id'].toString(),
        playerId: json['playerId'].toString(),
        playerName: json['playerName'] as String? ?? '',
        match: FootballMatch.fromJson(
          json['match'] as Map<String, dynamic>? ?? const {},
        ),
        position: json['position'] as String? ?? '',
        starter: json['starter'] as bool? ?? false,
        minutesPlayed: _asInt(json['minutesPlayed']),
        goals: _asInt(json['goals']),
        assists: _asInt(json['assists']),
        shots: _asInt(json['shots']),
        shotsOnTarget: _asInt(json['shotsOnTarget']),
        passesAttempted: _asInt(json['passesAttempted']),
        passesCompleted: _asInt(json['passesCompleted']),
        tackles: _asInt(json['tackles']),
        interceptions: _asInt(json['interceptions']),
        yellowCards: _asInt(json['yellowCards']),
        redCards: _asInt(json['redCards']),
        saves: _asInt(json['saves']),
        goalsConceded: _asInt(json['goalsConceded']),
        cleanSheet: json['cleanSheet'] as bool? ?? false,
        coachRating: _asNullableDouble(json['coachRating']),
        notes: json['notes'] as String? ?? '',
        ratingStatus: MatchRatingStatusWire.fromWire(
          json['ratingStatus'] as String?,
        ),
      );
}

/// Validated objective statistics sent by a Coordinator for one player.
class MatchPerformanceDraft {
  const MatchPerformanceDraft({
    required this.position,
    required this.starter,
    required this.minutesPlayed,
    required this.goals,
    required this.assists,
    required this.shots,
    required this.shotsOnTarget,
    required this.passesAttempted,
    required this.passesCompleted,
    required this.tackles,
    required this.interceptions,
    required this.yellowCards,
    required this.redCards,
    required this.saves,
    required this.goalsConceded,
    required this.cleanSheet,
  });

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
  };
}

class MatchRatingDraft {
  const MatchRatingDraft({required this.coachRating, required this.notes});

  final double coachRating;
  final String notes;

  Map<String, dynamic> toJson() => {
    'coachRating': coachRating,
    'notes': notes.trim(),
  };
}

class MatchRosterPlayer {
  const MatchRosterPlayer({
    required this.id,
    required this.name,
    required this.registeredPosition,
    required this.performance,
    required this.ratingStatus,
  });

  final String id;
  final String name;
  final String registeredPosition;
  final MatchPerformance? performance;
  final MatchRatingStatus ratingStatus;

  factory MatchRosterPlayer.fromJson(Map<String, dynamic> json) =>
      MatchRosterPlayer(
        id: json['id'].toString(),
        name: json['name'] as String? ?? '',
        registeredPosition: json['registeredPosition'] as String? ?? '',
        performance: json['performance'] is Map<String, dynamic>
            ? MatchPerformance.fromJson(
                json['performance'] as Map<String, dynamic>,
              )
            : null,
        ratingStatus: MatchRatingStatusWire.fromWire(
          json['ratingStatus'] as String?,
        ),
      );
}

class MatchPerformanceSummary {
  const MatchPerformanceSummary({
    required this.matchesPlayed,
    required this.starts,
    required this.minutesPlayed,
    required this.goals,
    required this.assists,
    required this.shots,
    required this.shotsOnTarget,
    required this.passesAttempted,
    required this.passesCompleted,
    required this.passCompletionRate,
    required this.tackles,
    required this.interceptions,
    required this.yellowCards,
    required this.redCards,
    required this.saves,
    required this.goalsConceded,
    required this.cleanSheets,
    required this.averageRating,
  });

  final int matchesPlayed;
  final int starts;
  final int minutesPlayed;
  final int goals;
  final int assists;
  final int shots;
  final int shotsOnTarget;
  final int passesAttempted;
  final int passesCompleted;
  final double? passCompletionRate;
  final int tackles;
  final int interceptions;
  final int yellowCards;
  final int redCards;
  final int saves;
  final int goalsConceded;
  final int cleanSheets;
  final double? averageRating;

  factory MatchPerformanceSummary.fromJson(Map<String, dynamic> json) =>
      MatchPerformanceSummary(
        matchesPlayed: _asInt(json['matchesPlayed']),
        starts: _asInt(json['starts']),
        minutesPlayed: _asInt(json['minutesPlayed']),
        goals: _asInt(json['goals']),
        assists: _asInt(json['assists']),
        shots: _asInt(json['shots']),
        shotsOnTarget: _asInt(json['shotsOnTarget']),
        passesAttempted: _asInt(json['passesAttempted']),
        passesCompleted: _asInt(json['passesCompleted']),
        passCompletionRate: _asNullableDouble(json['passCompletionRate']),
        tackles: _asInt(json['tackles']),
        interceptions: _asInt(json['interceptions']),
        yellowCards: _asInt(json['yellowCards']),
        redCards: _asInt(json['redCards']),
        saves: _asInt(json['saves']),
        goalsConceded: _asInt(json['goalsConceded']),
        cleanSheets: _asInt(json['cleanSheets']),
        averageRating: _asNullableDouble(json['averageRating']),
      );
}

class PlayerMatchStatistics {
  const PlayerMatchStatistics({
    required this.playerId,
    required this.playerName,
    required this.summary,
    required this.performances,
  });

  final String playerId;
  final String playerName;
  final MatchPerformanceSummary summary;
  final List<MatchPerformance> performances;

  factory PlayerMatchStatistics.fromJson(Map<String, dynamic> json) =>
      PlayerMatchStatistics(
        playerId: json['playerId'].toString(),
        playerName: json['playerName'] as String? ?? '',
        summary: MatchPerformanceSummary.fromJson(
          json['summary'] as Map<String, dynamic>? ?? const {},
        ),
        performances: (json['performances'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(MatchPerformance.fromJson)
            .toList(growable: false),
      );
}

int _asInt(dynamic value) => switch (value) {
  int number => number,
  num number => number.toInt(),
  String text => int.tryParse(text) ?? 0,
  _ => 0,
};

double? _asNullableDouble(dynamic value) => switch (value) {
  num number => number.toDouble(),
  String text => double.tryParse(text),
  _ => null,
};
