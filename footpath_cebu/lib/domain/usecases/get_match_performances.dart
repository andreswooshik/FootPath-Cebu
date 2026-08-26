import 'package:footpath_cebu/domain/entities/match_performance.dart';
import 'package:footpath_cebu/domain/repositories/match_repository.dart';

class GetMatchPerformances {
  const GetMatchPerformances(this._manager);

  final MatchManager _manager;

  Future<List<MatchPerformance>> call(String matchId) =>
      _manager.fetchMatchPerformances(matchId);
}
