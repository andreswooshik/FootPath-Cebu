import 'package:footpath_cebu/domain/entities/session_confirmation.dart';
import 'package:footpath_cebu/domain/repositories/session_confirmation_repository.dart';

/// Use case: record a player's RSVP for one training session.
class ConfirmSession {
  const ConfirmSession(this._repository);

  final SessionConfirmationWriter _repository;

  Future<SessionConfirmation> call(
    String sessionId,
    String playerId,
    ConfirmationStatus status,
  ) => _repository.confirmSession(sessionId, playerId, status);
}
