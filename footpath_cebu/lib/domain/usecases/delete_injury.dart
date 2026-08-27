import 'package:footpath_cebu/domain/entities/injury_record.dart';
import 'package:footpath_cebu/domain/repositories/injury_repository.dart';

/// Use case: remove one injury record from the player's history.
class DeleteInjury {
  const DeleteInjury(this._repository);

  final InjuryWriter _repository;

  Future<void> call(InjuryRecord record) => _repository.deleteInjury(record);
}
