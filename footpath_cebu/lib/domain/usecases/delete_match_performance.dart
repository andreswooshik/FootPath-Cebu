import 'package:footpath_cebu/domain/repositories/match_repository.dart';

class DeleteMatchPerformance {
  const DeleteMatchPerformance(this._manager);

  final MatchManager _manager;

  Future<void> call(String matchId, String playerId) =>
      _manager.deletePerformance(matchId, playerId);
}
