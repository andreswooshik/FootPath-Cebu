import 'package:footpath_cebu/domain/entities/training_session.dart';

/// Reads the coach's training schedule.
abstract class TrainingScheduleReader {
  /// Returns every session on the coach's calendar (past and upcoming).
  Future<List<TrainingSession>> fetchSessions();
}

/// Mutates the coach's calendar — create, edit, cancel.
abstract class TrainingScheduleWriter {
  /// Persists [draft] and returns the stored session (with its assigned id).
  Future<TrainingSession> createSession(TrainingSession draft);

  /// Saves changes to an existing session (matched by [session.id]) and
  /// returns the stored result.
  Future<TrainingSession> updateSession(TrainingSession session);

  /// Cancels (deletes) the session with [id]. Recorded attendance survives
  /// server-side; only the calendar entry goes away.
  Future<void> deleteSession(String id);
}

/// Aggregate of the training-schedule operations. Concrete data sources
/// implement this one interface, while each presentation provider depends only
/// on the narrow use case it needs (Interface Segregation) — the schedule list can't
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
