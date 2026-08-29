/// Where a completed football match was played.
enum MatchVenue { home, away, neutral }

enum MatchRecordSource { scheduled, adHoc }

extension MatchVenueInfo on MatchVenue {
  String get wire => name.toUpperCase();

  String get label => switch (this) {
    MatchVenue.home => 'Home',
    MatchVenue.away => 'Away',
    MatchVenue.neutral => 'Neutral',
  };

  static MatchVenue fromWire(String? value) => MatchVenue.values.firstWhere(
    (venue) => venue.wire == value?.toUpperCase(),
    orElse: () => MatchVenue.home,
  );
}

/// One completed match. Club ownership is intentionally server-managed.
class FootballMatch {
  const FootballMatch({
    required this.id,
    required this.opponent,
    required this.competition,
    required this.playedOn,
    required this.venue,
    required this.ourScore,
    required this.opponentScore,
    this.fixtureId,
    this.recordSource = MatchRecordSource.adHoc,
    this.ageBracketId,
    this.ageBracketLabel,
  });

  final String id;
  final String opponent;
  final String competition;
  final DateTime playedOn;
  final MatchVenue venue;
  final int ourScore;
  final int opponentScore;
  final String? fixtureId;
  final MatchRecordSource recordSource;
  final String? ageBracketId;
  final String? ageBracketLabel;

  bool get isAgeBracketMatch => ageBracketId != null;

  String get scoreLabel => '$ourScore–$opponentScore';

  String get outcome => ourScore > opponentScore
      ? 'Win'
      : ourScore < opponentScore
      ? 'Loss'
      : 'Draw';

  factory FootballMatch.fromJson(Map<String, dynamic> json) => FootballMatch(
    id: json['id'].toString(),
    opponent: json['opponent'] as String? ?? '',
    competition: json['competition'] as String? ?? '',
    playedOn: DateTime.parse(json['playedOn'] as String),
    venue: MatchVenueInfo.fromWire(json['venue'] as String?),
    ourScore: _asInt(json['ourScore']),
    opponentScore: _asInt(json['opponentScore']),
    fixtureId: json['fixtureId']?.toString(),
    recordSource: json['recordSource'] == 'SCHEDULED'
        ? MatchRecordSource.scheduled
        : MatchRecordSource.adHoc,
    ageBracketId: json['ageBracketId']?.toString(),
    ageBracketLabel: json['ageBracketLabel'] as String?,
  );
}

/// Coordinator-entered match metadata before server ownership is applied.
class FootballMatchDraft {
  const FootballMatchDraft({
    required this.opponent,
    required this.competition,
    required this.playedOn,
    required this.venue,
    required this.ourScore,
    required this.opponentScore,
    this.fixtureId,
  });

  final String opponent;
  final String competition;
  final DateTime playedOn;
  final MatchVenue venue;
  final int ourScore;
  final int opponentScore;
  final String? fixtureId;

  Map<String, dynamic> toJson() => {
    'opponent': opponent.trim(),
    'competition': competition.trim(),
    'playedOn': _dateOnly(playedOn),
    'venue': venue.wire,
    'ourScore': ourScore,
    'opponentScore': opponentScore,
    if (fixtureId != null) 'fixtureId': fixtureId,
  };
}

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

int _asInt(dynamic value) => switch (value) {
  int number => number,
  num number => number.toInt(),
  String text => int.tryParse(text) ?? 0,
  _ => 0,
};
