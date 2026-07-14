import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/domain/repositories/training_repository.dart';

/// Use case: load the coach's training schedule.
///
/// Depends on the narrow [TrainingScheduleReader] (Interface Segregation) — it
/// cannot create sessions.
class GetTrainingSessions {
  const GetTrainingSessions(this._repository);

  final TrainingScheduleReader _repository;

  Future<List<TrainingSession>> call() => _repository.fetchSessions();
}
