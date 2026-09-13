import 'dart:convert';

import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/entities/coordinator_person.dart';
import 'package:footpath_cebu/domain/repositories/coordinator_people_repository.dart';

class ApiCoordinatorPeopleRepository implements CoordinatorPeopleRepository {
  ApiCoordinatorPeopleRepository({AuthenticatedApiClient? api})
    : _api = api ?? AuthenticatedApiClient.shared;

  final AuthenticatedApiClient _api;

  String _path(CoordinatorPersonRole role, String id) =>
      '/api/coordinator/people/${role.path}/$id/';

  @override
  Future<CoordinatorPersonDetails> fetchDetails(
    CoordinatorPersonRole role,
    String id,
  ) async {
    try {
      final response = await _api.get(_path(role, id));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const ApiDecodeException(
          'The server returned invalid person details.',
        );
      }
      return CoordinatorPersonDetails.fromJson(decoded);
    } on FormatException {
      throw const CoordinatorPeopleRepositoryException(
        'The server returned invalid person details.',
      );
    } on ApiException catch (error) {
      throw CoordinatorPeopleRepositoryException(error.message);
    }
  }

  @override
  Future<void> deletePerson(CoordinatorPersonRole role, String id) async {
    try {
      await _api.delete(_path(role, id));
    } on ApiException catch (error) {
      throw CoordinatorPeopleRepositoryException(error.message);
    }
  }
}
