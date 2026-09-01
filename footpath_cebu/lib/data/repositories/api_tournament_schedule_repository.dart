import 'dart:convert';

import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
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
    TournamentDocumentUpload? document,
  }) => _write(() {
    final fields = {
      'title': title,
      'venue': venue,
      'startsOn': _dateOnly(startsOn),
    };
    if (document != null) {
      return _api.postMultipart(
        '/api/tournament-schedules/',
        fieldName: 'document',
        bytes: document.bytes,
        filename: document.filename,
        contentType: document.contentType,
        fields: fields,
        expectedStatuses: const {201},
      );
    }
    return _api.post(
      '/api/tournament-schedules/',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(fields),
      expectedStatuses: const {201},
    );
  });

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
    Set<AgeTier> academyTiers = const {},
    bool confirmTrainingCancellations = false,
  }) => _write(
    () => _api.post(
      '/api/tournament-schedules/$tournamentId/brackets/',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'maxAge': maxAge,
        'scheduledAt': scheduledAt?.toUtc().toIso8601String(),
        if (academyTiers.isNotEmpty)
          'academyTiers': academyTiers.map((tier) => tier.wire).toList(),
      }),
      expectedStatuses: const {201},
    ),
  );

  @override
  Future<TournamentSchedule> updateAgeBracket(
    String bracketId, {
    required int maxAge,
    DateTime? scheduledAt,
    Set<AgeTier> academyTiers = const {},
    bool confirmTrainingCancellations = false,
  }) => _write(
    () => _api.patch(
      '/api/tournament-brackets/$bracketId/',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'maxAge': maxAge,
        'scheduledAt': scheduledAt?.toUtc().toIso8601String(),
        if (academyTiers.isNotEmpty)
          'academyTiers': academyTiers.map((tier) => tier.wire).toList(),
        if (confirmTrainingCancellations) 'confirmTrainingCancellations': true,
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
  Future<TournamentSchedule> addFixture(
    String tournamentId,
    TournamentFixtureDraft fixture, {
    bool confirmTrainingCancellations = false,
  }) => _write(
    () => _api.post(
      '/api/tournament-schedules/$tournamentId/fixtures/',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        ...fixture.toJson(),
        if (confirmTrainingCancellations) 'confirmTrainingCancellations': true,
      }),
      expectedStatuses: const {201},
    ),
  );

  @override
  Future<TournamentSchedule> updateFixture(
    String fixtureId,
    TournamentFixtureDraft fixture, {
    bool confirmTrainingCancellations = false,
  }) => _write(
    () => _api.patch(
      '/api/tournament-fixtures/$fixtureId/',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        ...fixture.toJson(),
        if (confirmTrainingCancellations) 'confirmTrainingCancellations': true,
      }),
    ),
  );

  @override
  Future<void> deleteFixture(String fixtureId) async {
    try {
      await _api.delete('/api/tournament-fixtures/$fixtureId/');
    } on ApiException catch (error) {
      throw TournamentScheduleRepositoryException(
        error.message,
        statusCode: error is ApiHttpException ? error.statusCode : null,
      );
    }
  }

  @override
  Future<TournamentSchedule> uploadDocument(
    String tournamentId,
    TournamentDocumentUpload document,
  ) => _write(
    () => _api.postMultipart(
      '/api/tournament-schedules/$tournamentId/document/',
      fieldName: 'document',
      bytes: document.bytes,
      filename: document.filename,
      contentType: document.contentType,
    ),
  );

  @override
  Future<void> removeDocument(String tournamentId) async {
    try {
      await _api.delete('/api/tournament-schedules/$tournamentId/document/');
    } on ApiException catch (error) {
      throw TournamentScheduleRepositoryException(
        error.message,
        statusCode: error is ApiHttpException ? error.statusCode : null,
      );
    }
  }

  @override
  Future<void> deleteTournament(String tournamentId) async {
    try {
      await _api.delete('/api/tournament-schedules/$tournamentId/');
    } on ApiException catch (error) {
      throw TournamentScheduleRepositoryException(
        error.message,
        statusCode: error is ApiHttpException ? error.statusCode : null,
      );
    }
  }

  @override
  Future<TournamentSchedule> publishTournament(
    String tournamentId, {
    bool confirmTrainingCancellations = false,
  }) => _write(
    () => _api.post(
      '/api/tournament-schedules/$tournamentId/publish/',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (confirmTrainingCancellations) 'confirmTrainingCancellations': true,
      }),
    ),
  );

  @override
  Future<TournamentSchedule> recordResult(
    String fixtureId,
    TournamentResultDraft result,
  ) => _write(
    () => _api.post(
      '/api/tournament-fixtures/$fixtureId/result/',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(result.toJson()),
    ),
  );
}
