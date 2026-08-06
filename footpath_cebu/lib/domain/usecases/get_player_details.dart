import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';

class GetPlayerDetails {
  const GetPlayerDetails(this._repository);

  final PlayerDetailsReader _repository;

  Future<Player> call(String playerId, {String? unlockToken}) =>
      _repository.fetchPlayerDetails(playerId, unlockToken: unlockToken);
}
