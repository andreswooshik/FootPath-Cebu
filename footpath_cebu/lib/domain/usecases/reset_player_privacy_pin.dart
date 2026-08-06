import 'package:footpath_cebu/domain/entities/player_privacy_pin.dart';
import 'package:footpath_cebu/domain/repositories/player_privacy_pin_repository.dart';

class ResetPlayerPrivacyPin {
  const ResetPlayerPrivacyPin(this._repository);

  final PlayerPrivacyPinRepository _repository;

  Future<PlayerPrivacyPinStatus> call(String playerId) =>
      _repository.resetPin(playerId);
}
