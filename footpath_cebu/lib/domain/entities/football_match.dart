/// Where a completed football match was played.
enum MatchVenue { home, away, neutral }

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
  });

  final String id;
  final String opponent;
  final String competition;
  final DateTime playedOn;
  final MatchVenue venue;
  final int ourScore;
  final int opponentScore;

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
  );
}

/// Coach-entered match metadata before server ownership is applied.
class FootballMatchDraft {
  const FootballMatchDraft({
    required this.opponent,
    required this.competition,
    required this.playedOn,
    required this.venue,
    required this.ourScore,
    required this.opponentScore,
  });

  final String opponent;
  final String competition;
  final DateTime playedOn;
  final MatchVenue venue;
  final int ourScore;
  final int opponentScore;

  Map<String, dynamic> toJson() => {
    'opponent': opponent.trim(),
    'competition': competition.trim(),
    'playedOn': _dateOnly(playedOn),
    'venue': venue.wire,
    'ourScore': ourScore,
    'opponentScore': opponentScore,
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
