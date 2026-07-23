import 'package:footpath_cebu/domain/entities/player_progress.dart';
import 'package:footpath_cebu/domain/repositories/progress_repository.dart';

/// Use case: load the squad's attendance/effort aggregates for the coach's
/// Progress tab.
class GetSquadProgress {
  const GetSquadProgress(this._repository);

  final ProgressRepository _repository;

  Future<List<PlayerProgress>> call() => _repository.fetchSquadProgress();
}
