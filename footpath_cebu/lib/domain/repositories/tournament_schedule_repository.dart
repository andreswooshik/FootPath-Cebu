import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';

abstract interface class TournamentScheduleRepository {
  Future<List<TournamentSchedule>> fetchSchedules();
  Future<TournamentSchedule> createTournament({
    required String title,
    required String venue,
    required DateTime startsOn,
  });
  Future<TournamentSchedule> updateTournament(TournamentSchedule tournament);
  Future<TournamentSchedule> addAgeBracket(
    String tournamentId, {
    required int maxAge,
    DateTime? scheduledAt,
  });
  Future<TournamentSchedule> updateAgeBracket(
    String bracketId, {
    required int maxAge,
    DateTime? scheduledAt,
  });
  Future<void> deleteAgeBracket(String bracketId);
  Future<TournamentSchedule> publishTournament(String tournamentId);
}

class TournamentScheduleRepositoryException implements Exception {
  const TournamentScheduleRepositoryException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
