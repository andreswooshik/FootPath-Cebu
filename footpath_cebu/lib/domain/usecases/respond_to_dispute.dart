import 'package:footpath_cebu/domain/entities/dispute.dart';
import 'package:footpath_cebu/domain/repositories/dispute_repository.dart';

/// Use case: append one entry to a dispute's thread, optionally moving its
/// status. The thread is append-only — there is no edit or delete.
class RespondToDispute {
  const RespondToDispute(this._repository);

  final DisputeWriter _repository;

  Future<Dispute> call(
    String disputeId,
    String body, {
    DisputeStatus? statusChangeTo,
  }) =>
      _repository.respondToDispute(
        disputeId,
        body,
        statusChangeTo: statusChangeTo,
      );
}
