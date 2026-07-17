import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/injury_record.dart';

/// One player's injury history, most recent first. Family-keyed by player id
/// so the player's own screen and the coach's read-only view share caching.
final injuriesProvider =
    FutureProvider.autoDispose.family<List<InjuryRecord>, String>(
  (ref, playerId) => ref.watch(getInjuriesProvider)(playerId),
);

/// Drives the injury add/edit form and the delete action.
///
/// Owns only the submit state ([AsyncValue] loading/error); the field values
/// live in the form and are handed over as an [InjuryRecord] draft — same
/// shape as [EditPerformanceController].
class InjuryFormController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Creates or updates [record]. Returns the saved record on success, or
  /// null on failure (with the error in [state] for the View to show). On
  /// success the player's injury list is invalidated so every open view
  /// refreshes.
  Future<InjuryRecord?> submit(InjuryRecord record) async {
    state = const AsyncLoading();
    try {
      final saved = await ref.read(saveInjuryProvider)(record);
      state = const AsyncData(null);
      ref.invalidate(injuriesProvider(record.playerId));
      return saved;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }

  /// Deletes [record]. Returns true on success.
  Future<bool> remove(InjuryRecord record) async {
    final id = record.id;
    if (id == null) return false; // never saved — nothing to delete
    state = const AsyncLoading();
    try {
      await ref.read(deleteInjuryProvider)(id);
      state = const AsyncData(null);
      ref.invalidate(injuriesProvider(record.playerId));
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}

final injuryFormControllerProvider =
    AsyncNotifierProvider.autoDispose<InjuryFormController, void>(
  InjuryFormController.new,
);
