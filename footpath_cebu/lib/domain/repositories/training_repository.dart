import 'package:footpath_cebu/domain/entities/training_session.dart';

/// Reads the coach's training schedule.
abstract class TrainingScheduleReader {
  /// Returns every session on the coach's calendar (past and upcoming).
  Future<List<TrainingSession>> fetchSessions();
}

/// Creates new sessions on the coach's calendar.
abstract class TrainingScheduleWriter {
  /// Persists [draft] and returns the stored session (with its assigned id).
  Future<TrainingSession> createSession(TrainingSession draft);
}

/// Aggregate of the training-schedule operations. Concrete data sources
/// implement this one interface, while each ViewModel depends only on the
/// narrow use case it needs (Interface Segregation) — the schedule list can't
/// reach the writer, and the form can't reach the reader.
abstract class TrainingRepository
    implements TrainingScheduleReader, TrainingScheduleWriter {}

/// Thrown when a training-schedule operation cannot be completed.
class TrainingRepositoryException implements Exception {
  TrainingRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}
