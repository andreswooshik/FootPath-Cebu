import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/injury_record.dart';
import 'package:footpath_cebu/domain/entities/match_performance.dart';

void main() {
  test('match roster parses the confirmed injury warning', () {
    final player = MatchRosterPlayer.fromJson(const {
      'id': 'p1',
      'name': 'Ana Santos',
      'registeredPosition': 'CM',
      'performance': null,
      'ratingStatus': 'AWAITING_STATISTICS',
      'activeInjuryStatus': 'RECOVERING',
    });

    expect(player.activeInjuryStatus, InjuryStatus.recovering);
  });

  test('parses the match statistics wire contract', () {
    final statistics = PlayerMatchStatistics.fromJson({
      'playerId': 'p1',
      'playerName': 'Ana Santos',
      'summary': {
        'matchesPlayed': 2,
        'starts': 1,
        'minutesPlayed': 120,
        'goals': 1,
        'assists': 2,
        'shots': 4,
        'shotsOnTarget': 3,
        'passesAttempted': 50,
        'passesCompleted': 40,
        'passCompletionRate': 80.0,
        'tackles': 3,
        'interceptions': 2,
        'yellowCards': 1,
        'redCards': 0,
        'saves': 0,
        'goalsConceded': 0,
        'cleanSheets': 0,
        'averageRating': 8.25,
      },
      'performances': [
        {
          'id': 'perf1',
          'playerId': 'p1',
          'playerName': 'Ana Santos',
          'match': {
            'id': 'm1',
            'opponent': 'Cebu United',
            'competition': 'Youth League',
            'playedOn': '2026-08-20',
            'venue': 'HOME',
            'ourScore': 3,
            'opponentScore': 1,
          },
          'position': 'CM',
          'starter': true,
          'minutesPlayed': 80,
          'goals': 1,
          'assists': 2,
          'shots': 4,
          'shotsOnTarget': 3,
          'passesAttempted': 40,
          'passesCompleted': 32,
          'tackles': 3,
          'interceptions': 2,
          'yellowCards': 1,
          'redCards': 0,
          'saves': 0,
          'goalsConceded': 0,
          'cleanSheet': false,
          'coachRating': 8.5,
          'notes': 'Created chances.',
          'ratingStatus': 'RATED',
        },
      ],
    });

    expect(statistics.playerId, 'p1');
    expect(statistics.summary.passCompletionRate, 80);
    expect(statistics.summary.averageRating, 8.25);
    expect(statistics.performances.single.match.scoreLabel, '3–1');
    expect(statistics.performances.single.passCompletionRate, 80);
  });
}
