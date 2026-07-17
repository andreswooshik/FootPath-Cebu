import 'package:footpath_cebu/domain/entities/injury_record.dart';
import 'package:footpath_cebu/domain/repositories/injury_repository.dart';

/// Use case: load one player's injury history (most recent first).
class GetInjuries {
  const GetInjuries(this._repository);

  final InjuryReader _repository;

  Future<List<InjuryRecord>> call(String playerId) =>
      _repository.fetchInjuriesForPlayer(playerId);
}
