import 'package:footpath_cebu/domain/entities/match_performance.dart';
import 'package:footpath_cebu/domain/repositories/match_repository.dart';

class GetPlayerMatchStatistics {
  const GetPlayerMatchStatistics(this._reader);

  final MatchStatisticsReader _reader;

  Future<PlayerMatchStatistics> call(String playerId) =>
      _reader.fetchPlayerStatistics(playerId);
}
