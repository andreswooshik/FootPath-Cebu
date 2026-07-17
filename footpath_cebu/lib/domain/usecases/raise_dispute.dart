import 'package:footpath_cebu/domain/entities/dispute.dart';
import 'package:footpath_cebu/domain/repositories/dispute_repository.dart';

/// Use case: flag a new dispute (coach only — the server enforces the role).
class RaiseDispute {
  const RaiseDispute(this._repository);

  final DisputeWriter _repository;

  Future<Dispute> call({
    required DisputeCategory category,
    required String summary,
    String? detail,
    String? subjectPlayerId,
  }) =>
      _repository.raiseDispute(
        category: category,
        summary: summary,
        detail: detail,
        subjectPlayerId: subjectPlayerId,
      );
}
