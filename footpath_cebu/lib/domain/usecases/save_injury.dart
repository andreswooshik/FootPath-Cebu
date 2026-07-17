import 'package:footpath_cebu/domain/entities/injury_record.dart';
import 'package:footpath_cebu/domain/repositories/injury_repository.dart';

/// Use case: create or update one injury record (single upsert, matching the
/// [SavePlayerAssessment] precedent).
///
/// Depends on the narrow [InjuryWriter] (Interface Segregation).
class SaveInjury {
  const SaveInjury(this._repository);

  final InjuryWriter _repository;

  Future<InjuryRecord> call(InjuryRecord record) =>
      _repository.saveInjury(record);
}
