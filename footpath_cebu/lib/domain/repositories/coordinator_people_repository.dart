import 'package:footpath_cebu/domain/entities/coordinator_person.dart';

abstract interface class CoordinatorPeopleRepository {
  Future<CoordinatorPersonDetails> fetchDetails(
    CoordinatorPersonRole role,
    String id,
  );

  Future<void> deletePerson(CoordinatorPersonRole role, String id);
}

class CoordinatorPeopleRepositoryException implements Exception {
  const CoordinatorPeopleRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
