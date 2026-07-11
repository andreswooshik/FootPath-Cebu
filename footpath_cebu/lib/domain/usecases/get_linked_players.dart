import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';

/// Use case: load the players linked to the signed-in guardian.
class GetLinkedPlayers {
  const GetLinkedPlayers(this._repository);

  final LinkedPlayersRepository _repository;

  Future<List<Player>> call() => _repository.fetchLinkedPlayers();
}
