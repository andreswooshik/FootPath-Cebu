import 'package:footpath_cebu/domain/entities/tournament_schedule.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';

abstract interface class TournamentScheduleRepository {
  Future<List<TournamentSchedule>> fetchSchedules();
  Future<TournamentSchedule> createTournament({
    required String title,
    required String venue,
    required DateTime startsOn,
    TournamentDocumentUpload? document,
  });
  Future<TournamentSchedule> updateTournament(TournamentSchedule tournament);
  Future<TournamentSchedule> addAgeBracket(
    String tournamentId, {
    required int maxAge,
    DateTime? scheduledAt,
    Set<AgeTier> academyTiers = const {},
    bool confirmTrainingCancellations = false,
  });
  Future<TournamentSchedule> updateAgeBracket(
    String bracketId, {
    required int maxAge,
    DateTime? scheduledAt,
    Set<AgeTier> academyTiers = const {},
    bool confirmTrainingCancellations = false,
  });
  Future<void> deleteAgeBracket(String bracketId);
  Future<TournamentSchedule> addFixture(
    String tournamentId,
    TournamentFixtureDraft fixture, {
    bool confirmTrainingCancellations = false,
  });
  Future<TournamentSchedule> updateFixture(
    String fixtureId,
    TournamentFixtureDraft fixture, {
    bool confirmTrainingCancellations = false,
  });
  Future<void> deleteFixture(String fixtureId);
  Future<TournamentSchedule> uploadDocument(
    String tournamentId,
    TournamentDocumentUpload document,
  );
  Future<void> removeDocument(String tournamentId);
  Future<void> deleteTournament(String tournamentId);
  Future<TournamentSchedule> publishTournament(
    String tournamentId, {
    bool confirmTrainingCancellations = false,
  });
  Future<TournamentSchedule> recordResult(
    String fixtureId,
    TournamentResultDraft result,
  );
}

class TournamentScheduleRepositoryException implements Exception {
  const TournamentScheduleRepositoryException(
    this.message, {
    this.statusCode,
    this.code,
    this.details,
  });

  final String message;
  final int? statusCode;
  final String? code;
  final Map<String, dynamic>? details;

  @override
  String toString() => message;
}
