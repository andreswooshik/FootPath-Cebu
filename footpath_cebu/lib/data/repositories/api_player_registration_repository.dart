import 'dart:convert';

import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/entities/player_registration.dart';
import 'package:footpath_cebu/domain/repositories/player_registration_repository.dart';

class ApiPlayerRegistrationRepository implements PlayerRegistrationRepository {
  ApiPlayerRegistrationRepository({AuthenticatedApiClient? api})
    : _api = api ?? AuthenticatedApiClient.shared;
  final AuthenticatedApiClient _api;

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _api.post(
        path,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
        expectedStatuses: {200, 201},
      );
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on ApiHttpException catch (error) {
      final details = error.details;
      throw PlayerRegistrationException(
        _errorText(details ?? error.message),
        existingGuardianId: details?['existingGuardianId']?.toString(),
        uncertain: error.statusCode >= 500,
      );
    } on ApiException catch (error) {
      throw PlayerRegistrationException(error.message, uncertain: true);
    } catch (_) {
      throw const PlayerRegistrationException(
        'Could not confirm registration. Retry to check its status.',
        uncertain: true,
      );
    }
  }

  static String _errorText(Object value) {
    if (value is Map) {
      return value.entries
          .where((e) => e.key != 'existingGuardianId')
          .map((e) => _errorText(e.value))
          .join('\n');
    }
    if (value is List) {
      return value.map((item) => _errorText(item as Object)).join('\n');
    }
    return value.toString();
  }

  @override
  Future<void> checkGuardian(GuardianRegistrationData guardian) async {
    await _post('/api/coordinator/guardians/check/', guardian.toJson());
  }

  @override
  Future<PlayerRegistrationResult> register(
    PlayerRegistrationDraft draft,
  ) async => PlayerRegistrationResult.fromJson(
    await _post('/api/coordinator/player-registrations/', draft.toJson()),
  );
}
