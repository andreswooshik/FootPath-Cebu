import 'package:footpath_cebu/domain/entities/match_performance.dart';
import 'package:footpath_cebu/domain/repositories/match_repository.dart';

class GetMatchRoster {
  const GetMatchRoster(this._manager);

  final MatchManager _manager;

  Future<List<MatchRosterPlayer>> call(String matchId) =>
      _manager.fetchMatchRoster(matchId);
}
