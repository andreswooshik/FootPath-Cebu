import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/repositories/match_repository.dart';

class GetFootballMatches {
  const GetFootballMatches(this._manager);

  final MatchManager _manager;

  Future<List<FootballMatch>> call() => _manager.fetchMatches();
}
