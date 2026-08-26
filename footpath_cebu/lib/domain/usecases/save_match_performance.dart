import 'package:footpath_cebu/domain/entities/match_performance.dart';
import 'package:footpath_cebu/domain/repositories/match_repository.dart';

class SaveMatchPerformance {
  const SaveMatchPerformance(this._manager);

  final MatchManager _manager;

  Future<MatchPerformance> call(
    String matchId,
    String playerId,
    MatchPerformanceDraft draft,
  ) => _manager.savePerformance(matchId, playerId, draft);
}
