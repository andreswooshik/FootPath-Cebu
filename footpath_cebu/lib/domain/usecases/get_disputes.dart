import 'package:footpath_cebu/domain/entities/dispute.dart';
import 'package:footpath_cebu/domain/repositories/dispute_repository.dart';

/// Use case: load every dispute, newest first (server scopes by role).
class GetDisputes {
  const GetDisputes(this._repository);

  final DisputeReader _repository;

  Future<List<Dispute>> call() => _repository.fetchDisputes();
}
