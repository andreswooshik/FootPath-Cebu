import 'dart:convert';

import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';

/// Live player data backed by the authenticated Django REST API.
class ApiPlayerRepository
    implements PlayerRepository, PlayerDetailsReader, PlayerPhotoWriter {
  ApiPlayerRepository({this.unlockTokenFor, AuthenticatedApiClient? api})
    : _api = api ?? AuthenticatedApiClient.shared;

  final String? Function(String playerId)? unlockTokenFor;
  final AuthenticatedApiClient _api;

  @override
  Future<List<Player>> fetchSquad() => _getList('/api/players/');

  @override
  Future<List<Player>> fetchLinkedPlayers() => _getList('/api/players/linked/');

  @override
  Future<Player> fetchPlayerDetails(
    String playerId, {
    String? unlockToken,
  }) async {
    final token = unlockToken ?? unlockTokenFor?.call(playerId);
    final json = await _get(
      '/api/players/$playerId/profile/',
      extraHeaders: {
        if (token != null && token.isNotEmpty) 'X-Player-Unlock': token,
      },
    );
    return Player.fromJson(json);
  }

  @override
  Future<Player> fetchMyProfile() async {
    final json = await _get('/api/players/me/');
    return Player.fromJson(json);
  }

  @override
  Future<Player> savePosition(String playerId, PlayerPosition position) async {
    try {
      final response = await _api.put(
        '/api/players/$playerId/position/',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'position': position.wire}),
      );
      return Player.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } on ApiException catch (error) {
      throw PlayerRepositoryException(error.message);
    }
  }

  @override
  Future<Player> saveAssessment(
    String playerId,
    PlayerRatings ratings, {
    required String coachNotes,
  }) async {
    try {
      final response = await _api.put(
        '/api/players/$playerId/assessment/',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ratings': ratings.toJson(),
          'coachNotes': coachNotes,
        }),
      );
      return Player.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } on ApiException catch (error) {
      throw PlayerRepositoryException(error.message);
    }
  }

  @override
  Future<Player> uploadPhoto(
    String playerId, {
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    try {
      final response = await _api.postMultipart(
        '/api/players/$playerId/photo/',
        fieldName: 'photo',
        bytes: bytes,
        filename: filename,
        contentType: contentType,
      );
      return Player.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } on ApiException catch (error) {
      throw PlayerRepositoryException(error.message);
    } on FormatException {
      throw PlayerRepositoryException(
        'The server returned an invalid player profile.',
      );
    }
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String> extraHeaders = const {},
  }) async {
    try {
      final response = await _api.get(path, headers: extraHeaders);
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on ApiException catch (error) {
      throw PlayerRepositoryException(error.message);
    }
  }

  Future<List<Player>> _getList(String path) async {
    try {
      final response = await _api.get(path);
      final decoded = jsonDecode(response.body);
      final list = decoded is Map<String, dynamic>
          ? (decoded['results'] as List? ?? const [])
          : (decoded as List? ?? const []);
      return list
          .cast<Map<String, dynamic>>()
          .map(Player.fromJson)
          .toList(growable: false);
    } on ApiException catch (error) {
      throw PlayerRepositoryException(error.message);
    }
  }
}
