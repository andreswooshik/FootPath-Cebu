import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/injury_record.dart';

/// One player's injury history, most recent first. Family-keyed by player id
/// so the player's own screen and the coach's read-only view share caching.
final injuriesProvider = FutureProvider.autoDispose
    .family<List<InjuryRecord>, String>(
      (ref, playerId) => ref.watch(getInjuriesProvider)(playerId),
    );

final clubInjuriesProvider = FutureProvider.autoDispose<List<InjuryRecord>>(
  (ref) => ref.watch(injuryRepositoryProvider).fetchClubInjuries(),
);

final injuryReportablePlayersProvider =
    FutureProvider.autoDispose<List<InjuryPlayerOption>>(
      (ref) => ref.watch(injuryRepositoryProvider).fetchReportablePlayers(),
    );

/// Drives injury reporting, Pending-report management, and review actions.
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
      ref.invalidate(clubInjuriesProvider);
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
      await ref.read(deleteInjuryProvider)(record);
      state = const AsyncData(null);
      ref.invalidate(injuriesProvider(record.playerId));
      ref.invalidate(clubInjuriesProvider);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> reviewReport(
    InjuryRecord record, {
    required bool confirm,
    String rejectionReason = '',
  }) async {
    final id = record.id;
    if (id == null) return false;
    return _workflowAction(() {
      return ref
          .read(injuryRepositoryProvider)
          .reviewInjury(id, confirm: confirm, rejectionReason: rejectionReason);
    }, playerId: record.playerId);
  }

  Future<bool> archive(InjuryRecord record) async {
    final id = record.id;
    if (id == null) return false;
    return _workflowAction(
      () => ref.read(injuryRepositoryProvider).archiveInjury(id),
      playerId: record.playerId,
    );
  }

  Future<bool> requestStatus(
    InjuryRecord record,
    InjuryStatusUpdateDraft draft,
  ) async {
    return _workflowAction(
      () =>
          ref.read(injuryRepositoryProvider).requestStatusUpdate(record, draft),
      playerId: record.playerId,
    );
  }

  Future<bool> reviewStatus(
    InjuryRecord record, {
    required bool approve,
    String rejectionReason = '',
  }) async {
    final injuryId = record.id;
    final updateId = record.pendingStatusUpdate?.id;
    if (injuryId == null || updateId == null) return false;
    return _workflowAction(
      () => ref
          .read(injuryRepositoryProvider)
          .reviewStatusUpdate(
            injuryId,
            updateId,
            approve: approve,
            rejectionReason: rejectionReason,
          ),
      playerId: record.playerId,
    );
  }

  Future<bool> _workflowAction(
    Future<Object?> Function() action, {
    required String playerId,
  }) async {
    state = const AsyncLoading();
    try {
      await action();
      state = const AsyncData(null);
      ref.invalidate(injuriesProvider(playerId));
      ref.invalidate(clubInjuriesProvider);
      return true;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return false;
    }
  }
}

final injuryFormControllerProvider =
    AsyncNotifierProvider.autoDispose<InjuryFormController, void>(
      InjuryFormController.new,
    );
