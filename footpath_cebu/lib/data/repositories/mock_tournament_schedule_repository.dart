import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/tournament_roster.dart';
import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';
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
        startsOn: now.add(const Duration(days: 5)),
        isPublished: true,
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
    required DateTime startsOn,
  }) async {
    await fetchSchedules();
    final now = DateTime.now();
    final created = TournamentSchedule(
      id: 'schedule-${_schedules.length + 1}',
      title: title,
      startsOn: startsOn,
      isPublished: false,
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
  }) async {
    final tournament = _schedules.firstWhere((row) => row.id == tournamentId);
    final bracket = TournamentAgeBracket(
      id: 'bracket-${DateTime.now().microsecondsSinceEpoch}',
      maxAge: maxAge,
      label: 'U$maxAge',
      scheduledAt: scheduledAt,
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
  Future<TournamentSchedule> publishTournament(String tournamentId) async {
    final tournament = _schedules.firstWhere((row) => row.id == tournamentId);
    final now = DateTime.now();
    final updated = tournament.copyWith(
      isPublished: true,
      publishedAt: now,
      updatedAt: now,
    );
    _replace(updated);
    return updated;
  }
}
