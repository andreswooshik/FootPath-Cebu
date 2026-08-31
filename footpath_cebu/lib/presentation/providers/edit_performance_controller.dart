import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/development_assessment.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/presentation/providers/growth_providers.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';

/// Drives the coach's Edit Performance Data form.
///
/// Owns only the submit state ([AsyncValue] loading/error); the observed
/// indicator values live in the screen and are submitted as one draft.
class EditPerformanceController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Persists a five-domain [draft] for [playerId]. Returns the updated
  /// player on success, or null on failure (with the error in [state] for the
  /// View to show). On success, roster and growth providers are invalidated so
  /// all five-domain summaries refresh immediately.
  Future<Player?> submit(
    String playerId,
    DevelopmentAssessmentDraft draft,
  ) async {
    state = const AsyncLoading();
    try {
      final updated = await ref.read(saveDevelopmentAssessmentProvider)(
        playerId,
        draft,
      );
      state = const AsyncData(null);
      ref.invalidate(squadProvider);
      ref.invalidate(playerGrowthProvider);
      ref.invalidate(developmentAssessmentFormProvider(playerId));
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
