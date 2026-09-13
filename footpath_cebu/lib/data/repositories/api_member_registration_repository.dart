import 'dart:convert';

import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/entities/member_registration.dart';
import 'package:footpath_cebu/domain/repositories/member_registration_repository.dart';

class ApiMemberRegistrationRepository implements MemberRegistrationRepository {
  ApiMemberRegistrationRepository({AuthenticatedApiClient? api})
    : _api = api ?? AuthenticatedApiClient.shared;

  final AuthenticatedApiClient _api;

  @override
  Future<MemberRegistrationResult> create(
    MemberAccountRole role,
    MemberRegistrationData data,
  ) async {
    try {
      final response = await _api.post(
        '/api/coordinator/member-registrations/',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data.toJson(role)),
        expectedStatuses: {201},
      );
      return MemberRegistrationResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on ApiHttpException catch (error) {
      throw MemberRegistrationException(
        _errorText(error.details ?? error.message),
      );
    } on ApiException catch (error) {
      throw MemberRegistrationException(error.message);
    } catch (_) {
      throw const MemberRegistrationException(
        'Could not create the account. Check your connection and retry.',
      );
    }
  }

  static String _errorText(Object value) {
    if (value is Map) {
      return value.values.map((item) => _errorText(item as Object)).join('\n');
    }
    if (value is List) {
      return value.map((item) => _errorText(item as Object)).join('\n');
    }
    return value.toString();
  }
}
