import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/match_performance.dart';
import 'package:footpath_cebu/domain/repositories/match_repository.dart';

const _mockMatchPlayers = [
  ('p1', 'Rhobert Ronaldo', 'ST'),
  ('p2', 'Ralf Andre Messi', 'CAM'),
  ('p3', 'Reiner Neymar', 'LW'),
  ('p4', 'Kevin De Bofill', 'CM'),
  ('p5', 'Virgil Van Cortez', 'CB'),
  ('p6', 'Trent Alexander Cruz', 'RB'),
  ('p7', 'Gianluigi Dela Cruz', 'GK'),
  ('p8', 'Jude Belino', 'CM'),
  ('p9', 'Lamine Yamashita', 'RW'),
  ('p10', 'Pedri Villanueva', ''),
  ('p11', 'Liam Tan', 'GK'),
];

/// Stateful in-memory match store for UI development and widget tests.
class MockMatchRepository implements MatchRepository {
  final List<FootballMatch> _matches = [
    FootballMatch(
      id: 'm1',
      opponent: 'Cebu United',
      competition: 'Cebu Youth League',
      playedOn: DateTime.now().subtract(const Duration(days: 7)),
      venue: MatchVenue.home,
      ourScore: 3,
      opponentScore: 1,
      category: MatchCategory.league,
    ),
    FootballMatch(
      id: 'm2',
      opponent: 'Mandaue FC',
      competition: 'Cebu Youth League',
      playedOn: DateTime.now().subtract(const Duration(days: 21)),
      venue: MatchVenue.away,
      ourScore: 1,
      opponentScore: 1,
      category: MatchCategory.league,
    ),
    FootballMatch(
      id: 'm3',
      opponent: 'Lapu-Lapu Academy',
      competition: 'Cebu Youth Cup',
      playedOn: DateTime.now().subtract(const Duration(days: 35)),
      venue: MatchVenue.neutral,
      ourScore: 1,
      opponentScore: 2,
      category: MatchCategory.tournament,
    ),
  ];

  final List<MatchPerformance> _performances = [];

  MockMatchRepository() {
    _performances.addAll([
      _sample(_matches[0], rating: 8.7, goals: 2, assists: 1),
      _sample(
        _matches[1],
        rating: 7.4,
        goals: 0,
        assists: 1,
        passesAttempted: 30,
        passesCompleted: 23,
        tackles: 2,
      ),
      _sample(
        _matches[2],
        rating: 6.9,
        goals: 0,
        assists: 0,
        passesAttempted: 27,
        passesCompleted: 18,
        tackles: 1,
      ),
    ]);
    for (
      var playerIndex = 1;
      playerIndex < _mockMatchPlayers.length;
      playerIndex++
    ) {
      final player = _mockMatchPlayers[playerIndex];
      for (var matchIndex = 0; matchIndex < _matches.length; matchIndex++) {
        final isGoalkeeper = player.$3 == 'GK';
        final intentionallyUnrated = player.$1 == 'p11' && matchIndex == 2;
        _performances.add(
          _sample(
            _matches[matchIndex],
            playerId: player.$1,
            playerName: player.$2,
            position: player.$3,
            rating: intentionallyUnrated
                ? null
                : 7.9 - playerIndex * 0.1 - matchIndex * 0.2,
            goals: isGoalkeeper
                ? 0
                : (playerIndex + matchIndex) % 3 == 0
                ? 1
                : 0,
            assists: isGoalkeeper
                ? 0
                : (playerIndex + matchIndex) % 4 == 0
                ? 1
                : 0,
            passesAttempted: 22 + playerIndex + matchIndex,
            passesCompleted: 17 + playerIndex,
            tackles: isGoalkeeper ? 0 : 1 + playerIndex % 3,
          ),
        );
      }
    }
  }

  MatchPerformance _sample(
    FootballMatch match, {
    required double? rating,
    required int goals,
    required int assists,
    int passesAttempted = 28,
    int passesCompleted = 22,
    int tackles = 1,
    String playerId = 'p1',
    String playerName = 'Rhobert Ronaldo',
    String position = 'ST',
  }) => MatchPerformance(
    id: 'perf-${match.id}-$playerId',
    playerId: playerId,
    playerName: playerName,
    match: match,
    position: position,
    starter: true,
    minutesPlayed: 80,
    goals: goals,
    assists: assists,
    shots: 5,
    shotsOnTarget: 3,
    passesAttempted: passesAttempted,
    passesCompleted: passesCompleted,
    tackles: tackles,
    interceptions: 0,
    yellowCards: 0,
    redCards: 0,
    saves: position == 'GK' ? 4 : 0,
    goalsConceded: position == 'GK' ? match.opponentScore : 0,
    cleanSheet: position == 'GK' && match.opponentScore == 0,
    coachRating: rating,
    notes: 'Strong movement and decision-making.',
    ratingStatus: rating == null
        ? MatchRatingStatus.awaitingRating
        : MatchRatingStatus.rated,
  );

  @override
  Future<List<FootballMatch>> fetchMatches() async => List.unmodifiable(
    [..._matches]..sort((a, b) => b.playedOn.compareTo(a.playedOn)),
  );

  @override
  Future<FootballMatch> createMatch(FootballMatchDraft draft) async {
    final match = FootballMatch(
      id: 'm${_matches.length + 1}',
      opponent: draft.opponent.trim(),
      competition: draft.competition.trim(),
      playedOn: draft.playedOn,
      venue: draft.venue,
      ourScore: draft.ourScore,
      opponentScore: draft.opponentScore,
      fixtureId: draft.fixtureId,
      recordSource: draft.fixtureId == null
          ? MatchRecordSource.adHoc
          : MatchRecordSource.scheduled,
      category: draft.category,
    );
    _matches.add(match);
    return match;
  }

  @override
  Future<FootballMatch> updateMatch(
    String matchId,
    FootballMatchDraft draft,
  ) async {
    final index = _matches.indexWhere((match) => match.id == matchId);
    if (index < 0) throw const MatchRepositoryException('Match not found.');
    final updated = FootballMatch(
      id: matchId,
      opponent: draft.opponent.trim(),
      competition: draft.competition.trim(),
      playedOn: draft.playedOn,
      venue: draft.venue,
      ourScore: draft.ourScore,
      opponentScore: draft.opponentScore,
      fixtureId: _matches[index].fixtureId,
      recordSource: _matches[index].recordSource,
      ageBracketId: _matches[index].ageBracketId,
      ageBracketLabel: _matches[index].ageBracketLabel,
      category: draft.category,
    );
    _matches[index] = updated;
    return updated;
  }

  @override
  Future<List<MatchPerformance>> fetchMatchPerformances(String matchId) async =>
      _performances
          .where((performance) => performance.match.id == matchId)
          .toList(growable: false);

  @override
  Future<List<MatchRosterPlayer>> fetchMatchRoster(
    String matchId, {
    bool includeOutOfSquad = false,
  }) async {
    final rows = await fetchMatchPerformances(matchId);
    final byPlayer = {for (final row in rows) row.playerId: row};
    return [
      for (final entry in _mockMatchPlayers)
        MatchRosterPlayer(
          id: entry.$1,
          name: entry.$2,
          registeredPosition: entry.$3,
          performance: byPlayer[entry.$1],
          ratingStatus:
              byPlayer[entry.$1]?.ratingStatus ??
              MatchRatingStatus.awaitingStatistics,
        ),
    ];
  }

  @override
  Future<MatchPerformance> savePerformance(
    String matchId,
    String playerId,
    MatchPerformanceDraft draft,
  ) async {
    final match = _matches.firstWhere(
      (item) => item.id == matchId,
      orElse: () => throw const MatchRepositoryException('Match not found.'),
    );
    final existing = _performances.indexWhere(
      (item) => item.match.id == matchId && item.playerId == playerId,
    );
    final performance = MatchPerformance(
      id: existing < 0 ? 'perf-$matchId-$playerId' : _performances[existing].id,
      playerId: playerId,
      playerName: existing < 0
          ? 'Player $playerId'
          : _performances[existing].playerName,
      match: match,
      position: draft.position,
      starter: draft.starter,
      minutesPlayed: draft.minutesPlayed,
      goals: draft.goals,
      assists: draft.assists,
      shots: draft.shots,
      shotsOnTarget: draft.shotsOnTarget,
      passesAttempted: draft.passesAttempted,
      passesCompleted: draft.passesCompleted,
      tackles: draft.tackles,
      interceptions: draft.interceptions,
      yellowCards: draft.yellowCards,
      redCards: draft.redCards,
      saves: draft.saves,
      goalsConceded: draft.goalsConceded,
      cleanSheet: draft.cleanSheet,
      coachRating: existing < 0 ? null : _performances[existing].coachRating,
      notes: existing < 0 ? '' : _performances[existing].notes,
      ratingStatus: existing < 0
          ? MatchRatingStatus.awaitingRating
          : _performances[existing].ratingStatus,
    );
    if (existing < 0) {
      _performances.add(performance);
    } else {
      _performances[existing] = performance;
    }
    return performance;
  }

  @override
  Future<void> deletePerformance(String matchId, String playerId) async {
    _performances.removeWhere(
      (item) => item.match.id == matchId && item.playerId == playerId,
    );
  }

  @override
  Future<MatchPerformance> saveRating(
    String matchId,
    String playerId,
    MatchRatingDraft draft,
  ) async {
    final index = _performances.indexWhere(
      (item) => item.match.id == matchId && item.playerId == playerId,
    );
    if (index < 0) {
      throw const MatchRepositoryException(
        'Coordinator statistics must be recorded first.',
      );
    }
    final row = _performances[index];
    final updated = _copyPerformance(
      row,
      coachRating: draft.coachRating,
      notes: draft.notes,
      ratingStatus: MatchRatingStatus.rated,
    );
    _performances[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteRating(String matchId, String playerId) async {
    final index = _performances.indexWhere(
      (item) => item.match.id == matchId && item.playerId == playerId,
    );
    if (index < 0) return;
    _performances[index] = _copyPerformance(
      _performances[index],
      clearRating: true,
      ratingStatus: MatchRatingStatus.awaitingRating,
    );
  }

  @override
  Future<PlayerMatchStatistics> fetchPlayerStatistics(String playerId) async {
    final rows = _performances
        .where((performance) => performance.playerId == playerId)
        .toList(growable: false);
    final attempted = rows.fold<int>(
      0,
      (total, row) => total + row.passesAttempted,
    );
    final completed = rows.fold<int>(
      0,
      (total, row) => total + row.passesCompleted,
    );
    return PlayerMatchStatistics(
      playerId: playerId,
      playerName: rows.isEmpty ? 'Player $playerId' : rows.first.playerName,
      summary: MatchPerformanceSummary(
        matchesPlayed: rows.length,
        starts: rows.where((row) => row.starter).length,
        minutesPlayed: rows.fold(0, (sum, row) => sum + row.minutesPlayed),
        goals: rows.fold(0, (sum, row) => sum + row.goals),
        assists: rows.fold(0, (sum, row) => sum + row.assists),
        shots: rows.fold(0, (sum, row) => sum + row.shots),
        shotsOnTarget: rows.fold(0, (sum, row) => sum + row.shotsOnTarget),
        passesAttempted: attempted,
        passesCompleted: completed,
        passCompletionRate: attempted == 0 ? null : completed * 100 / attempted,
        tackles: rows.fold(0, (sum, row) => sum + row.tackles),
        interceptions: rows.fold(0, (sum, row) => sum + row.interceptions),
        yellowCards: rows.fold(0, (sum, row) => sum + row.yellowCards),
        redCards: rows.fold(0, (sum, row) => sum + row.redCards),
        saves: rows.fold(0, (sum, row) => sum + row.saves),
        goalsConceded: rows.fold(0, (sum, row) => sum + row.goalsConceded),
        cleanSheets: rows.where((row) => row.cleanSheet).length,
        averageRating: rows.where((row) => row.coachRating != null).isEmpty
            ? null
            : rows
                      .where((row) => row.coachRating != null)
                      .fold<double>(0, (sum, row) => sum + row.coachRating!) /
                  rows.where((row) => row.coachRating != null).length,
      ),
      performances: rows,
    );
  }

  MatchPerformance _copyPerformance(
    MatchPerformance row, {
    double? coachRating,
    String? notes,
    bool clearRating = false,
    MatchRatingStatus? ratingStatus,
  }) => MatchPerformance(
    id: row.id,
    playerId: row.playerId,
    playerName: row.playerName,
    match: row.match,
    position: row.position,
    starter: row.starter,
    minutesPlayed: row.minutesPlayed,
    goals: row.goals,
    assists: row.assists,
    shots: row.shots,
    shotsOnTarget: row.shotsOnTarget,
    passesAttempted: row.passesAttempted,
    passesCompleted: row.passesCompleted,
    tackles: row.tackles,
    interceptions: row.interceptions,
    yellowCards: row.yellowCards,
    redCards: row.redCards,
    saves: row.saves,
    goalsConceded: row.goalsConceded,
    cleanSheet: row.cleanSheet,
    coachRating: clearRating ? null : (coachRating ?? row.coachRating),
    notes: clearRating ? '' : (notes ?? row.notes),
    ratingStatus: ratingStatus ?? row.ratingStatus,
  );
}
