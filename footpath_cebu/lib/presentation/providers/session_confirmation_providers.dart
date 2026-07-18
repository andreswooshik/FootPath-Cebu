import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/session_confirmation.dart';

/// One player's session confirmations. Family-keyed by player id so the
/// schedule screen's cards can each look up their own session's status.
final sessionConfirmationsProvider =
    FutureProvider.autoDispose.family<List<SessionConfirmation>, String>(
  (ref, playerId) => ref.watch(getSessionConfirmationsProvider)(playerId),
);

/// Drives the Confirm/Decline action on a schedule card.
///
/// Owns only the submit state ([AsyncValue] loading/error) — same shape as
/// [ScheduleSessionController].
class SessionConfirmationController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Records [status] for [sessionId]/[playerId]. On success the player's
  /// confirmation list is invalidated so every open view refreshes.
  Future<bool> submit(
    String sessionId,
    String playerId,
    ConfirmationStatus status,
  ) async {
    state = const AsyncLoading();
    try {
      await ref.read(confirmSessionProvider)(sessionId, playerId, status);
      state = const AsyncData(null);
      ref.invalidate(sessionConfirmationsProvider(playerId));
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}

final sessionConfirmationControllerProvider =
    AsyncNotifierProvider.autoDispose<SessionConfirmationController, void>(
  SessionConfirmationController.new,
);
