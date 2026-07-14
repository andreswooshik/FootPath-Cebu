import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/domain/repositories/training_repository.dart';

/// Use case: schedule a new training session.
///
/// Depends on the narrow [TrainingScheduleWriter] (Interface Segregation) — it
/// cannot read the existing schedule.
class ScheduleTrainingSession {
  const ScheduleTrainingSession(this._repository);

  final TrainingScheduleWriter _repository;

  Future<TrainingSession> call(TrainingSession draft) =>
      _repository.createSession(draft);
}
