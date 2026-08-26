import 'package:footpath_cebu/domain/entities/football_match.dart';
import 'package:footpath_cebu/domain/repositories/match_repository.dart';

class CreateFootballMatch {
  const CreateFootballMatch(this._manager);

  final MatchManager _manager;

  Future<FootballMatch> call(FootballMatchDraft draft) =>
      _manager.createMatch(draft);
}
