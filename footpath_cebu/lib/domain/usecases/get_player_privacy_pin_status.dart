import 'package:footpath_cebu/domain/entities/player_privacy_pin.dart';
import 'package:footpath_cebu/domain/repositories/player_privacy_pin_repository.dart';

class GetPlayerPrivacyPinStatus {
  const GetPlayerPrivacyPinStatus(this._repository);

  final PlayerPrivacyPinRepository _repository;

  Future<PlayerPrivacyPinStatus> call(String playerId) =>
      _repository.fetchStatus(playerId);
}
