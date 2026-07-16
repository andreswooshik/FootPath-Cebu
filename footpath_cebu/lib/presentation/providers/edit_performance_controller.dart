import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';

/// Drives the coach's Edit Performance Data form.
///
/// Owns only the submit state ([AsyncValue] loading/error); the slider values
/// live in the screen and are handed over as a [PlayerRatings] draft.
class EditPerformanceController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Persists [ratings] for [playerId]. Returns the updated player on success,
  /// or null on failure (with the error in [state] for the View to show).
  /// On success the squad roster is invalidated so the card's overall rating
  /// refreshes wherever it is shown.
  Future<Player?> submit(String playerId, PlayerRatings ratings) async {
    state = const AsyncLoading();
    try {
      final updated =
          await ref.read(savePlayerAssessmentProvider)(playerId, ratings);
      state = const AsyncData(null);
      ref.invalidate(squadProvider);
      return updated;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }
}

final editPerformanceControllerProvider =
    AsyncNotifierProvider.autoDispose<EditPerformanceController, void>(
  EditPerformanceController.new,
);
