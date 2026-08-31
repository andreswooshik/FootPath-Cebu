import 'dart:convert';

import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/entities/player_growth.dart';
import 'package:footpath_cebu/domain/repositories/growth_repository.dart';

class ApiGrowthRepository implements GrowthRepository {
  ApiGrowthRepository({this.unlockTokenFor, AuthenticatedApiClient? api})
    : _api = api ?? AuthenticatedApiClient.shared;

  final String? Function(String playerId)? unlockTokenFor;
  final AuthenticatedApiClient _api;

  @override
  Future<PlayerGrowth> fetchGrowth(GrowthQuery query) async {
    final params = <String, String>{
      'range': query.range.wire,
      'category': query.category.wire,
      if (query.from != null) 'from': _dateOnly(query.from!),
      if (query.to != null) 'to': _dateOnly(query.to!),
    };
    final path = Uri(
      path: '/api/players/${query.playerId}/growth/',
      queryParameters: params,
    ).toString();
    final unlockToken = unlockTokenFor?.call(query.playerId);
    try {
      final response = await _api.get(
        path,
        headers: {
          if (unlockToken != null && unlockToken.isNotEmpty)
            'X-Player-Unlock': unlockToken,
        },
      );
      return PlayerGrowth.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on ApiHttpException catch (error) {
      throw GrowthRepositoryException(
        error.message,
        statusCode: error.statusCode,
      );
    } on ApiException catch (error) {
      throw GrowthRepositoryException(error.message);
    } on FormatException {
      throw const GrowthRepositoryException(
        'The server returned invalid player growth data.',
      );
    }
  }
}

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
