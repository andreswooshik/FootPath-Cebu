import 'package:footpath_cebu/domain/entities/match_performance.dart';
import 'package:footpath_cebu/domain/repositories/match_repository.dart';

class SaveMatchRating {
  const SaveMatchRating(this._manager);

  final MatchManager _manager;

  Future<MatchPerformance> call(
    String matchId,
    String playerId,
    MatchRatingDraft draft,
  ) => _manager.saveRating(matchId, playerId, draft);
}
