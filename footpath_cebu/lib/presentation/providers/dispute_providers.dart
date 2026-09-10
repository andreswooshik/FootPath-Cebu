import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/presentation/providers/mutation_controller.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/dispute.dart';

/// Every dispute, newest first (the backend scopes access by role).
final disputesProvider = FutureProvider.autoDispose<List<Dispute>>(
  (ref) => ref.watch(getDisputesProvider)(),
);

final disputeDetailProvider = FutureProvider.autoDispose
    .family<Dispute, String>((ref, id) => ref.watch(getDisputeProvider)(id));

/// Drives the flag-dispute form and the respond action.
///
/// Owns only the submit state ([AsyncValue] loading/error); field values live
/// in the screens — same shape as [InjuryFormController].
class DisputeFormController extends MutationController {
  /// Flags a new dispute. Returns it on success, or null on failure (with
  /// the error in [state] for the View to show).
  Future<Dispute?> raise({
    required DisputeCategory category,
    required String summary,
    String? detail,
    String? subjectPlayerId,
  }) async {
    return runMutation(
      () async {
        final dispute = await ref.read(raiseDisputeProvider)(
          category: category,
          summary: summary,
          detail: detail,
          subjectPlayerId: subjectPlayerId,
        );
        return dispute;
      },
      onSuccess: (result) {
        ref.invalidate(disputesProvider);
      },
    );
  }

  /// Appends a response (optionally moving the status). Returns the updated
  /// dispute on success, or null on failure.
  Future<Dispute?> respond(
    String disputeId,
    String body, {
    DisputeStatus? statusChangeTo,
  }) async {
    return runMutation(
      () async {
        final dispute = await ref.read(respondToDisputeProvider)(
          disputeId,
          body,
          statusChangeTo: statusChangeTo,
        );
        return dispute;
      },
      onSuccess: (result) {
        ref.invalidate(disputesProvider);
        ref.invalidate(disputeDetailProvider(disputeId));
      },
    );
  }
}

final disputeFormControllerProvider =
    AsyncNotifierProvider.autoDispose<DisputeFormController, void>(
      DisputeFormController.new,
    );
