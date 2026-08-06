import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/session_confirmation.dart';

/// One player's session confirmations. Family-keyed by player id so the
/// schedule screen's cards can each look up their own session's status.
final sessionConfirmationsProvider = FutureProvider.autoDispose
    .family<List<SessionConfirmation>, String>(
      (ref, playerId) => ref.watch(getSessionConfirmationsProvider)(playerId),
    );

/// Drives the Confirm/Decline action on the schedule cards.
///
/// State is the set of session ids with a submit in flight — not a single
/// shared loading flag. Each card checks its *own* session, so tapping Confirm
/// on one session only spins that card's button, never every card at once.
class SessionConfirmationController extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  /// Whether [sessionId]'s button should show its in-progress spinner.
  bool isSubmitting(String sessionId) => state.contains(sessionId);

  /// Records [status] for [sessionId]/[playerId]. On success the player's
  /// confirmation list is invalidated so every open view refreshes.
  Future<bool> submit(
    String sessionId,
    String playerId,
    ConfirmationStatus status,
  ) async {
    if (state.contains(sessionId)) return false; // already submitting
    state = {...state, sessionId};
    try {
      await ref.read(confirmSessionProvider)(sessionId, playerId, status);
      ref.invalidate(sessionConfirmationsProvider(playerId));
      return true;
    } catch (_) {
      return false;
    } finally {
      state = state.where((id) => id != sessionId).toSet();
    }
  }
}

final sessionConfirmationControllerProvider =
    NotifierProvider.autoDispose<SessionConfirmationController, Set<String>>(
      SessionConfirmationController.new,
    );
