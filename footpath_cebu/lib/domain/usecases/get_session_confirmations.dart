import 'package:footpath_cebu/domain/entities/session_confirmation.dart';
import 'package:footpath_cebu/domain/repositories/session_confirmation_repository.dart';

/// Use case: load one player's session confirmations.
class GetSessionConfirmations {
  const GetSessionConfirmations(this._repository);

  final SessionConfirmationReader _repository;

  Future<List<SessionConfirmation>> call(String playerId) =>
      _repository.fetchConfirmationsForPlayer(playerId);
}