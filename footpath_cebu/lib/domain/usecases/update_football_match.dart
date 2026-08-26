import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/repositories/match_repository.dart';

class UpdateFootballMatch {
  const UpdateFootballMatch(this._manager);

  final MatchManager _manager;

  Future<FootballMatch> call(String matchId, FootballMatchDraft draft) =>
      _manager.updateMatch(matchId, draft);
}
