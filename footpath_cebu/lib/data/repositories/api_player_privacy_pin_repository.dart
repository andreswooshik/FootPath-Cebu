import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:footpath_cebu/core/config/api_config.dart';
import 'package:footpath_cebu/domain/entities/player_privacy_pin.dart';
import 'package:footpath_cebu/domain/repositories/player_privacy_pin_repository.dart';
import 'package:http/http.dart' as http;

class ApiPlayerPrivacyPinRepository implements PlayerPrivacyPinRepository {
  @override
  Future<PlayerPrivacyPinStatus> fetchStatus(String playerId) async {
    final response = await _request('GET', '/api/players/$playerId/pin/');
    return PlayerPrivacyPinStatus.fromJson(_body(response));
  }

  @override
  Future<PlayerPrivacyPinStatus> setPin(
    String playerId, {
    required String pin,
    String? currentPin,
  }) async {
    final response = await _request(
      'PUT',
      '/api/players/$playerId/pin/',
      body: {'pin': pin, 'currentPin': ?currentPin},
    );
    return PlayerPrivacyPinStatus.fromJson(_body(response));
  }

  @override
  Future<void> verifyPin(String playerId, String pin) async {
    final response = await _request(
      'POST',
      '/api/players/$playerId/pin/verify/',
      body: {'pin': pin},
    );
    if (response.statusCode != 200) {
      throw PlayerPrivacyPinException(_errorMessage(response));
    }
  }

  @override
  Future<PlayerPrivacyPinStatus> resetPin(String playerId) async {
    final response = await _request(
      'POST',
      '/api/players/$playerId/pin/reset/',
      forceRefreshToken: true,
    );
    return PlayerPrivacyPinStatus.fromJson(_body(response));
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool forceRefreshToken = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const PlayerPrivacyPinException('Not signed in.');
    final token = await user.getIdToken(forceRefreshToken);
    if (token == null) throw const PlayerPrivacyPinException('Not signed in.');
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    try {
      final headers = {
        'Authorization': 'Bearer $token',
        if (body != null) 'Content-Type': 'application/json',
      };
      return switch (method) {
        'GET' => await http.get(uri, headers: headers),
        'PUT' => await http.put(uri, headers: headers, body: jsonEncode(body)),
        _ => await http.post(uri, headers: headers, body: jsonEncode(body)),
      };
    } catch (_) {
      throw const PlayerPrivacyPinException(
        'Could not reach the server. Is it running?',
      );
    }
  }

  Map<String, dynamic> _body(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PlayerPrivacyPinException(_errorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  String _errorMessage(http.Response response) {
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final detail = json['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
      final first = json.values.firstWhere(
        (value) => value is List && value.isNotEmpty,
        orElse: () => null,
      );
      if (first is List && first.isNotEmpty) return first.first.toString();
    } catch (_) {
      // Fall through to the status-code message.
    }
    if (response.statusCode == 423) return 'The PIN is temporarily locked.';
    return 'PIN request failed (${response.statusCode}).';
  }
}
