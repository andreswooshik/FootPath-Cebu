import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';

/// Use case: assign or change the position a coach has decided for a player.
///
/// Depends on the narrow [PositionWriter] (Interface Segregation) — it can set
/// a position but cannot reach any read or the ratings write.
class SavePlayerPosition {
  const SavePlayerPosition(this._repository);

  final PositionWriter _repository;

  Future<Player> call(String playerId, PlayerPosition position) =>
      _repository.savePosition(playerId, position);
}
