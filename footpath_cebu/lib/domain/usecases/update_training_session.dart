import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/domain/repositories/training_repository.dart';

/// Use case: save changes to an already-scheduled training session.
///
/// Depends on the narrow [TrainingScheduleWriter] (Interface Segregation) — it
/// cannot read the existing schedule.
class UpdateTrainingSession {
  const UpdateTrainingSession(this._repository);

  final TrainingScheduleWriter _repository;

  Future<TrainingSession> call(TrainingSession session) =>
      _repository.updateSession(session);
}
