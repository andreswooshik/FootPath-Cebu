import 'dart:convert';

import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';
import 'package:footpath_cebu/domain/repositories/tournament_schedule_repository.dart';

class ApiTournamentScheduleRepository implements TournamentScheduleRepository {
  ApiTournamentScheduleRepository({AuthenticatedApiClient? api})
    : _api = api ?? AuthenticatedApiClient.shared;

  final AuthenticatedApiClient _api;

  @override
  Future<List<TournamentSchedule>> fetchSchedules() async {
    try {
      final response = await _api.get('/api/tournament-schedules/');
      return (jsonDecode(response.body) as List)
          .cast<Map<String, dynamic>>()
          .map(TournamentSchedule.fromJson)
          .toList(growable: false);
    } on ApiException catch (error) {
      throw TournamentScheduleRepositoryException(
        error.message,
        statusCode: error is ApiHttpException ? error.statusCode : null,
      );
    }
  }
}
