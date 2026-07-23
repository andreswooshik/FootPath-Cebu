import 'package:footpath_cebu/domain/repositories/training_repository.dart';

/// Use case: cancel (delete) a scheduled training session.
///
/// Depends on the narrow [TrainingScheduleWriter] (Interface Segregation) — it
/// cannot read the existing schedule.
class CancelTrainingSession {
  const CancelTrainingSession(this._repository);

  final TrainingScheduleWriter _repository;

  Future<void> call(String sessionId) => _repository.deleteSession(sessionId);
}
