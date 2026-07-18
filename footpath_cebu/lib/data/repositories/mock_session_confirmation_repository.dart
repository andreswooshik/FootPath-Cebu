import 'package:footpath_cebu/domain/entities/session_confirmation.dart';
import 'package:footpath_cebu/domain/repositories/session_confirmation_repository.dart';

/// In-memory session confirmations for UI development without a backend.
/// Instance state (not static) so each test gets a clean slate while the
/// app — which builds one instance per run — still sees edits persist
/// across screens.
class MockSessionConfirmationRepository
    implements SessionConfirmationRepository {
  final List<SessionConfirmation> _records = [];

  @override
  Future<List<SessionConfirmation>> fetchConfirmationsForPlayer(
    String playerId,
  ) async {
    // Simulate network latency so loading states are exercised in the UI.
    await Future.delayed(const Duration(milliseconds: 300));
    final records =
        _records.where((c) => c.playerId == playerId).toList()
          ..sort((a, b) => b.respondedAt.compareTo(a.respondedAt));
    return List.unmodifiable(records);
  }

  @override
  Future<SessionConfirmation> confirmSession(
    String sessionId,
    String playerId,
    ConfirmationStatus status,
  ) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final confirmation = SessionConfirmation(
      sessionId: sessionId,
      playerId: playerId,
      status: status,
      respondedAt: DateTime.now(),
    );
    _records.removeWhere(
      (c) => c.sessionId == sessionId && c.playerId == playerId,
    );
    _records.add(confirmation);
    return confirmation;
  }
}