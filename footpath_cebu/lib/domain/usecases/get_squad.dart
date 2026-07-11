import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';

/// Use case: load the coach's active squad roster.
///
/// Depends on the narrow [SquadRepository] (Interface Segregation) — it cannot
/// reach player-self or guardian reads.
class GetSquad {
  const GetSquad(this._repository);

  final SquadRepository _repository;

  Future<List<Player>> call() => _repository.fetchSquad();
}
