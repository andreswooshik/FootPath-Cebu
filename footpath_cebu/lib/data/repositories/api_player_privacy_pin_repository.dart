import 'dart:convert';

import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/entities/player_privacy_pin.dart';
import 'package:footpath_cebu/domain/repositories/player_privacy_pin_repository.dart';

class ApiPlayerPrivacyPinRepository implements PlayerPrivacyPinRepository {
  ApiPlayerPrivacyPinRepository({AuthenticatedApiClient? api})
    : _api = api ?? AuthenticatedApiClient.shared;

  final AuthenticatedApiClient _api;

  @override
  Future<PlayerPrivacyPinStatus> fetchStatus(String playerId) async {
    try {
      // PIN lockout/configuration state must always be authoritative; it is not
      // one of the ordinary offline-readable core records.
      final response = await _api.get(
        '/api/players/$playerId/pin/',
        cache: false,
      );
      return PlayerPrivacyPinStatus.fromJson(_body(response.body));
    } on ApiException catch (error) {
      throw PlayerPrivacyPinException(_message(error));
    }
  }

  @override
  Future<PlayerPrivacyPinStatus> setPin(
    String playerId, {
    required String pin,
    String? currentPin,
  }) async {
    try {
      final response = await _api.put(
        '/api/players/$playerId/pin/',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'pin': pin, 'currentPin': ?currentPin}),
      );
      return PlayerPrivacyPinStatus.fromJson(_body(response.body));
    } on ApiException catch (error) {
      throw PlayerPrivacyPinException(_message(error));
    }
  }

  @override
  Future<String> verifyPin(String playerId, String pin) async {
    try {
      final response = await _api.post(
        '/api/players/$playerId/pin/verify/',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'pin': pin}),
      );
      final token = _body(response.body)['unlockToken'];
      if (token is! String || token.isEmpty) {
        throw const PlayerPrivacyPinException(
          'The server did not return a profile unlock.',
        );
      }
      return token;
    } on ApiException catch (error) {
      throw PlayerPrivacyPinException(_message(error));
    }
  }

  @override
  Future<PlayerPrivacyPinStatus> resetPin(String playerId) async {
    try {
      final response = await _api.post(
        '/api/players/$playerId/pin/reset/',
        forceRefreshToken: true,
      );
      return PlayerPrivacyPinStatus.fromJson(_body(response.body));
    } on ApiException catch (error) {
      throw PlayerPrivacyPinException(_message(error));
    }
  }

  Map<String, dynamic> _body(String body) =>
      jsonDecode(body) as Map<String, dynamic>;

  String _message(ApiException error) =>
      error is ApiHttpException && error.statusCode == 423
      ? 'The PIN is temporarily locked.'
      : error.message;
}
