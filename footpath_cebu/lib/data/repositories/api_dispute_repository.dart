import 'dart:convert';

import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/data/dto/dispute_dto.dart';
import 'package:footpath_cebu/domain/entities/dispute.dart';
import 'package:footpath_cebu/domain/repositories/dispute_repository.dart';

/// Live dispute data backed by the authenticated Django REST API.
class ApiDisputeRepository implements DisputeRepository {
  ApiDisputeRepository({AuthenticatedApiClient? api})
    : _api = api ?? AuthenticatedApiClient.shared;

  static const _path = '/api/disputes/';

  final AuthenticatedApiClient _api;

  @override
  Future<Dispute> fetchDispute(String disputeId) async {
    try {
      final response = await _api.get('$_path$disputeId/');
      return DisputeDto.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on ApiException catch (error) {
      throw DisputeRepositoryException(error.message);
    } on FormatException {
      throw DisputeRepositoryException(
        'The server returned an invalid dispute.',
      );
    }
  }

  @override
  Future<List<Dispute>> fetchDisputes() async {
    try {
      final list = await _api.getList(_path);
      return list.map(DisputeDto.fromJson).toList(growable: false);
    } on ApiException catch (error) {
      throw DisputeRepositoryException(error.message);
    }
  }

  @override
  Future<Dispute> raiseDispute({
    required DisputeCategory category,
    required String summary,
    String? detail,
    String? subjectPlayerId,
  }) async {
    try {
      final response = await _api.post(
        _path,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'category': DisputeDto.categoryToWire(category),
          'summary': summary,
          'detail': ?detail,
          'subjectPlayerId': ?subjectPlayerId,
        }),
        expectedStatuses: const {201},
      );
      return DisputeDto.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on ApiException catch (error) {
      throw DisputeRepositoryException(error.message);
    }
  }

  @override
  Future<Dispute> respondToDispute(
    String disputeId,
    String body, {
    DisputeStatus? statusChangeTo,
  }) async {
    try {
      final response = await _api.post(
        '$_path$disputeId/responses/',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'body': body,
          if (statusChangeTo != null)
            'statusChangeTo': DisputeDto.statusToWire(statusChangeTo),
        }),
        expectedStatuses: const {201},
      );
      return DisputeDto.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on ApiException catch (error) {
      throw DisputeRepositoryException(error.message);
    }
  }
}
