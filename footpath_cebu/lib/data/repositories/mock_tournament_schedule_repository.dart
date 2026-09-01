import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/tournament_roster.dart';
import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/repositories/tournament_schedule_repository.dart';

class MockTournamentScheduleRepository implements TournamentScheduleRepository {
  final List<TournamentSchedule> _schedules = [];

  @override
  Future<List<TournamentSchedule>> fetchSchedules() async {
    if (_schedules.isNotEmpty) return List.unmodifiable(_schedules);
    final now = DateTime.now();
    _schedules.addAll([
      TournamentSchedule(
        id: 'schedule-1',
        title: 'Cebu Youth Cup',
        venue: 'Cebu City Sports Center',
        startsOn: now.add(const Duration(days: 5)),
        isPublished: true,
        lifecycleStatus: TournamentLifecycleStatus.published,
        hasDocument: false,
        documentUrl: null,
        publishedAt: now.subtract(const Duration(days: 10)),
        updatedAt: now.subtract(const Duration(days: 1)),
        ageBrackets: [
          TournamentAgeBracket(
            id: 'bracket-1',
            maxAge: 12,
            label: 'U12',
            squad: TournamentSquad(
              id: 'squad-1',
              bracketId: 'bracket-1',
              status: TournamentSquadStatus.published,
              publishedAt: now.subtract(const Duration(days: 1)),
              entries: const [
                TournamentSquadEntry(
                  id: 'entry-1',
                  playerId: '1',
                  playerName: 'Alex Santos',
                  tournamentPosition: 'CM',
                ),
              ],
            ),
          ),
        ],
        fixtures: [
          TournamentFixture(
            id: 'fixture-1',
            scheduleId: 'schedule-1',
            tournament: 'Cebu Youth Cup',
            stage: 'Group A',
            opponent: 'Lapu-Lapu United',
            kickoffAt: now.subtract(const Duration(days: 1)),
            venue: MatchVenue.neutral,
            location: 'Cebu City Sports Center',
            status: TournamentFixtureStatus.scheduled,
          ),
          TournamentFixture(
            id: 'fixture-2',
            scheduleId: 'schedule-1',
            tournament: 'Cebu Youth Cup',
            stage: 'Group A',
            opponent: 'Mandaue FC',
            kickoffAt: now.add(const Duration(days: 5)),
            venue: MatchVenue.away,
            location: 'Mandaue Sports Complex',
            status: TournamentFixtureStatus.scheduled,
          ),
        ],
      ),
    ]);
    return List.unmodifiable(_schedules);
  }

  void _replace(TournamentSchedule value) {
    final index = _schedules.indexWhere((row) => row.id == value.id);
    if (index >= 0) _schedules[index] = value;
  }

  @override
  Future<TournamentSchedule> createTournament({
    required String title,
    required String venue,
    required DateTime startsOn,
    TournamentDocumentUpload? document,
  }) async {
    await fetchSchedules();
    final now = DateTime.now();
    final created = TournamentSchedule(
      id: 'schedule-${_schedules.length + 1}',
      title: title,
      venue: venue,
      startsOn: startsOn,
      isPublished: false,
      lifecycleStatus: TournamentLifecycleStatus.draft,
      hasDocument: document != null,
      publishedAt: null,
      updatedAt: now,
      ageBrackets: const [],
      fixtures: const [],
    );
    _schedules.insert(0, created);
    return created;
  }

  @override
  Future<TournamentSchedule> updateTournament(
    TournamentSchedule tournament,
  ) async {
    final updated = tournament.copyWith(updatedAt: DateTime.now());
    _replace(updated);
    return updated;
  }

  @override
  Future<TournamentSchedule> addAgeBracket(
    String tournamentId, {
    required int maxAge,
    DateTime? scheduledAt,
    Set<AgeTier> academyTiers = const {},
    bool confirmTrainingCancellations = false,
  }) async {
    final tournament = _schedules.firstWhere((row) => row.id == tournamentId);
    final bracket = TournamentAgeBracket(
      id: 'bracket-${DateTime.now().microsecondsSinceEpoch}',
      maxAge: maxAge,
      label: 'U$maxAge',
      scheduledAt: scheduledAt,
      academyTiers: academyTiers,
    );
    final updated = tournament.copyWith(
      ageBrackets: [...tournament.ageBrackets, bracket]
        ..sort((a, b) => a.maxAge.compareTo(b.maxAge)),
      updatedAt: DateTime.now(),
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<TournamentSchedule> updateAgeBracket(
    String bracketId, {
    required int maxAge,
    DateTime? scheduledAt,
    Set<AgeTier> academyTiers = const {},
    bool confirmTrainingCancellations = false,
  }) async {
    final tournament = _schedules.firstWhere(
      (row) => row.ageBrackets.any((bracket) => bracket.id == bracketId),
    );
    final brackets = tournament.ageBrackets.map((bracket) {
      if (bracket.id != bracketId) return bracket;
      return TournamentAgeBracket(
        id: bracket.id,
        maxAge: maxAge,
        label: 'U$maxAge',
        scheduledAt: scheduledAt,
        academyTiers: academyTiers,
      );
    }).toList()..sort((a, b) => a.maxAge.compareTo(b.maxAge));
    final updated = tournament.copyWith(
      ageBrackets: brackets,
      updatedAt: DateTime.now(),
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<void> deleteAgeBracket(String bracketId) async {
    final tournament = _schedules.firstWhere(
      (row) => row.ageBrackets.any((bracket) => bracket.id == bracketId),
    );
    _replace(
      tournament.copyWith(
        ageBrackets: tournament.ageBrackets
            .where((bracket) => bracket.id != bracketId)
            .toList(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<TournamentSchedule> addFixture(
    String tournamentId,
    TournamentFixtureDraft fixture, {
    bool confirmTrainingCancellations = false,
  }) async {
    final tournament = _schedules.firstWhere((row) => row.id == tournamentId);
    final bracket = tournament.ageBrackets.firstWhere(
      (row) => row.id == fixture.ageBracketId,
    );
    final created = TournamentFixture(
      id: 'fixture-${DateTime.now().microsecondsSinceEpoch}',
      scheduleId: tournament.id,
      tournament: tournament.title,
      stage: fixture.stage,
      opponent: fixture.opponent.trim().isEmpty ? 'TBD' : fixture.opponent,
      kickoffAt: fixture.kickoffAt,
      endsAt: fixture.endsAt,
      venue: fixture.venue,
      location: fixture.location,
      status: fixture.status,
      ageBracketId: bracket.id,
      ageBracketLabel: bracket.label,
    );
    final updated = tournament.copyWith(
      fixtures: [...tournament.fixtures, created]
        ..sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt)),
      updatedAt: DateTime.now(),
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<TournamentSchedule> updateFixture(
    String fixtureId,
    TournamentFixtureDraft fixture, {
    bool confirmTrainingCancellations = false,
  }) async {
    final tournament = _schedules.firstWhere(
      (row) => row.fixtures.any((item) => item.id == fixtureId),
    );
    final bracket = tournament.ageBrackets.firstWhere(
      (row) => row.id == fixture.ageBracketId,
    );
    final fixtures = tournament.fixtures.map((item) {
      if (item.id != fixtureId) return item;
      return TournamentFixture(
        id: item.id,
        scheduleId: item.scheduleId,
        tournament: tournament.title,
        stage: fixture.stage,
        opponent: fixture.opponent.trim().isEmpty ? 'TBD' : fixture.opponent,
        kickoffAt: fixture.kickoffAt,
        endsAt: fixture.endsAt,
        venue: fixture.venue,
        location: fixture.location,
        status: fixture.status,
        ageBracketId: bracket.id,
        ageBracketLabel: bracket.label,
      );
    }).toList()..sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));
    final updated = tournament.copyWith(
      fixtures: fixtures,
      updatedAt: DateTime.now(),
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<void> deleteFixture(String fixtureId) async {
    final tournament = _schedules.firstWhere(
      (row) => row.fixtures.any((item) => item.id == fixtureId),
    );
    _replace(
      tournament.copyWith(
        fixtures: tournament.fixtures
            .where((item) => item.id != fixtureId)
            .toList(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<TournamentSchedule> uploadDocument(
    String tournamentId,
    TournamentDocumentUpload document,
  ) async {
    final tournament = _schedules.firstWhere((row) => row.id == tournamentId);
    final updated = tournament.copyWith(
      hasDocument: true,
      updatedAt: DateTime.now(),
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<void> removeDocument(String tournamentId) async {
    final tournament = _schedules.firstWhere((row) => row.id == tournamentId);
    _replace(
      tournament.copyWith(hasDocument: false, updatedAt: DateTime.now()),
    );
  }

  @override
  Future<void> deleteTournament(String tournamentId) async {
    _schedules.removeWhere((row) => row.id == tournamentId);
  }

  @override
  Future<TournamentSchedule> publishTournament(
    String tournamentId, {
    bool confirmTrainingCancellations = false,
  }) async {
    final tournament = _schedules.firstWhere((row) => row.id == tournamentId);
    final now = DateTime.now();
    final updated = tournament.copyWith(
      isPublished: true,
      lifecycleStatus: TournamentLifecycleStatus.published,
      publishedAt: now,
      updatedAt: now,
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<TournamentSchedule> recordResult(
    String fixtureId,
    TournamentResultDraft result,
  ) async {
    final tournament = _schedules.firstWhere(
      (row) => row.fixtures.any((item) => item.id == fixtureId),
    );
    final fixtures = tournament.fixtures.map((item) {
      if (item.id != fixtureId) return item;
      final match = FootballMatch(
        id: 'match-${DateTime.now().microsecondsSinceEpoch}',
        opponent: item.opponent,
        competition: tournament.title,
        playedOn: item.kickoffAt,
        venue: item.venue,
        ourScore: result.ourScore,
        opponentScore: result.opponentScore,
        category: MatchCategory.tournament,
      );
      return TournamentFixture(
        id: item.id,
        scheduleId: item.scheduleId,
        tournament: item.tournament,
        stage: item.stage,
        opponent: item.opponent,
        kickoffAt: item.kickoffAt,
        venue: item.venue,
        location: item.location,
        status: TournamentFixtureStatus.completed,
        matchId: match.id,
        ageBracketId: item.ageBracketId,
        ageBracketLabel: item.ageBracketLabel,
        ourScore: result.ourScore,
        opponentScore: result.opponentScore,
        outcome: result.ourScore > result.opponentScore
            ? 'WIN'
            : result.ourScore < result.opponentScore
            ? 'LOSS'
            : 'DRAW',
        linkedMatch: match,
      );
    }).toList();
    final allDone = fixtures.every(
      (item) =>
          item.status == TournamentFixtureStatus.completed ||
          item.status == TournamentFixtureStatus.cancelled,
    );
    final updated = tournament.copyWith(
      fixtures: fixtures,
      lifecycleStatus: allDone
          ? TournamentLifecycleStatus.completed
          : TournamentLifecycleStatus.inProgress,
      updatedAt: DateTime.now(),
    );
    _replace(updated);
    return updated;
  }
}
