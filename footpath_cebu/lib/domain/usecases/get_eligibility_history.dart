import 'package:footpath_cebu/domain/entities/eligibility_change.dart';
import 'package:footpath_cebu/domain/repositories/eligibility_history_repository.dart';

/// Fetches a player's eligibility transition history, newest first.
class GetEligibilityHistory {
  GetEligibilityHistory(this._repository);
  final EligibilityHistoryRepository _repository;

  Future<List<EligibilityChange>> call(
    String playerId, {
    String? unlockToken,
  }) => _repository.fetchHistoryForPlayer(playerId, unlockToken: unlockToken);
}
