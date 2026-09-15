import 'package:flutter_test/flutter_test.dart';

import 'package:footpath_cebu/data/repositories/mock_attendance_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_growth_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_match_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_player_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_tournament_schedule_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_training_repository.dart';
import 'package:footpath_cebu/domain/entities/player_growth.dart';
import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';

void main() {
  test('every mock squad player has connected historical data', () async {
    final players = await MockPlayerRepository().fetchSquad();
    final attendance = MockAttendanceRepository();
    final matches = MockMatchRepository();
    final growth = MockGrowthRepository();
    final sessions = await MockTrainingRepository().fetchSessions();

    expect(
      sessions.where((session) => session.hasEndedAt(DateTime.now())),
      isNotEmpty,
    );
    for (final player in players) {
      expect(
        player.developmentAssessment,
        isNotNull,
        reason: '${player.name} needs a current development assessment',
      );
      expect(
        await attendance.fetchAttendanceForPlayer(player.id),
        isNotEmpty,
        reason: '${player.name} needs attendance history',
      );
      final statistics = await matches.fetchPlayerStatistics(player.id);
      expect(
        statistics.performances.length,
        greaterThanOrEqualTo(2),
        reason: '${player.name} needs match history',
      );
      final playerGrowth = await growth.fetchGrowth(
        GrowthQuery(playerId: player.id),
      );
      expect(playerGrowth.playerName, player.name);
      expect(playerGrowth.developmentAssessments.length, 2);
      expect(playerGrowth.assessments.length, 2);
      expect(playerGrowth.regularMatches?.history.length, 2);
    }
  });

  test('Liam Tan has tournament history and an unrated coach action', () async {
    final players = await MockPlayerRepository().fetchSquad();
    final liam = players.singleWhere((player) => player.name == 'Liam Tan');
    final statistics = await MockMatchRepository().fetchPlayerStatistics(
      liam.id,
    );
    final schedules = await MockTournamentScheduleRepository().fetchSchedules();
    final tournament = schedules.single;

    expect(
      statistics.performances.any(
        (performance) => performance.coachRating == null,
      ),
      isTrue,
    );
    expect(
      tournament.ageBrackets.single.squad!.entries.any(
        (entry) => entry.playerId == liam.id,
      ),
      isTrue,
    );
    expect(
      tournament.fixtures.any(
        (fixture) => fixture.status == TournamentFixtureStatus.completed,
      ),
      isTrue,
    );
    expect(
      tournament.fixtures.any((fixture) => fixture.opponent == 'TBD'),
      isTrue,
    );
  });
}
