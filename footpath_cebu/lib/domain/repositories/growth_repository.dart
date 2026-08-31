import 'package:footpath_cebu/domain/entities/player_growth.dart';

abstract interface class GrowthRepository {
  Future<PlayerGrowth> fetchGrowth(GrowthQuery query);
}

class GrowthRepositoryException implements Exception {
  const GrowthRepositoryException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
