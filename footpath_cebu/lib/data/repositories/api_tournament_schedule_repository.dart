import 'dart:convert';

import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';
import 'package:footpath_cebu/domain/repositories/tournament_schedule_repository.dart';

class ApiTournamentScheduleRepository implements TournamentScheduleRepository {
  ApiTournamentScheduleRepository({AuthenticatedApiClient? api})
    : _api = api ?? AuthenticatedApiClient.shared;

  final AuthenticatedApiClient _api;

  static String _dateOnly(DateTime value) =>
      value.toIso8601String().split('T').first;

  Future<TournamentSchedule> _write(Future<dynamic> Function() request) async {
    try {
      final response = await request();
      return TournamentSchedule.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on ApiException catch (error) {
      throw TournamentScheduleRepositoryException(
        error.message,
        statusCode: error is ApiHttpException ? error.statusCode : null,
      );
    }
  }

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

  @override
  Future<TournamentSchedule> createTournament({
    required String title,
    required String venue,
    required DateTime startsOn,
  }) => _write(
    () => _api.post(
      '/api/tournament-schedules/',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'title': title,
        'venue': venue,
        'startsOn': _dateOnly(startsOn),
      }),
      expectedStatuses: const {201},
    ),
  );

  @override
  Future<TournamentSchedule> updateTournament(TournamentSchedule tournament) =>
      _write(
        () => _api.patch(
          '/api/tournament-schedules/${tournament.id}/',
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'title': tournament.title,
            'venue': tournament.venue,
            'startsOn': _dateOnly(tournament.startsOn),
          }),
        ),
      );

  @override
  Future<TournamentSchedule> addAgeBracket(
    String tournamentId, {
    required int maxAge,
    DateTime? scheduledAt,
  }) => _write(
    () => _api.post(
      '/api/tournament-schedules/$tournamentId/brackets/',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'maxAge': maxAge,
        'scheduledAt': scheduledAt?.toUtc().toIso8601String(),
      }),
      expectedStatuses: const {201},
    ),
  );

  @override
  Future<TournamentSchedule> updateAgeBracket(
    String bracketId, {
    required int maxAge,
    DateTime? scheduledAt,
  }) => _write(
    () => _api.patch(
      '/api/tournament-brackets/$bracketId/',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'maxAge': maxAge,
        'scheduledAt': scheduledAt?.toUtc().toIso8601String(),
      }),
    ),
  );

  @override
  Future<void> deleteAgeBracket(String bracketId) async {
    try {
      await _api.delete('/api/tournament-brackets/$bracketId/');
    } on ApiException catch (error) {
      throw TournamentScheduleRepositoryException(
        error.message,
        statusCode: error is ApiHttpException ? error.statusCode : null,
      );
    }
  }

  @override
  Future<TournamentSchedule> publishTournament(String tournamentId) => _write(
    () => _api.post('/api/tournament-schedules/$tournamentId/publish/'),
  );
}
