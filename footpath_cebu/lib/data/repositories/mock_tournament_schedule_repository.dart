import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';
import 'package:footpath_cebu/domain/repositories/tournament_schedule_repository.dart';

class MockTournamentScheduleRepository implements TournamentScheduleRepository {
  @override
  Future<List<TournamentSchedule>> fetchSchedules() async {
    final now = DateTime.now();
    return [
      TournamentSchedule(
        id: 'schedule-1',
        title: 'Cebu Youth Cup',
        documentUrl: null,
        publishedAt: now.subtract(const Duration(days: 10)),
        updatedAt: now.subtract(const Duration(days: 1)),
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
    ];
  }
}
