import 'package:footpath_cebu/domain/repositories/match_repository.dart';

class DeleteMatchRating {
  const DeleteMatchRating(this._manager);

  final MatchManager _manager;

  Future<void> call(String matchId, String playerId) =>
      _manager.deleteRating(matchId, playerId);
}
