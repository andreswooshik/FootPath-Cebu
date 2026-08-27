import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';

abstract interface class TournamentScheduleRepository {
  Future<List<TournamentSchedule>> fetchSchedules();
}

class TournamentScheduleRepositoryException implements Exception {
  const TournamentScheduleRepositoryException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
