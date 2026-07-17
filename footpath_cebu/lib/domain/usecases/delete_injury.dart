import 'package:footpath_cebu/domain/repositories/injury_repository.dart';

/// Use case: remove one injury record from the player's history.
class DeleteInjury {
  const DeleteInjury(this._repository);

  final InjuryWriter _repository;

  Future<void> call(String injuryId) => _repository.deleteInjury(injuryId);
}
