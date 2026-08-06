import 'package:footpath_cebu/domain/entities/player_privacy_pin.dart';
import 'package:footpath_cebu/domain/repositories/player_privacy_pin_repository.dart';

class SetPlayerPrivacyPin {
  const SetPlayerPrivacyPin(this._repository);

  final PlayerPrivacyPinRepository _repository;

  Future<PlayerPrivacyPinStatus> call(
    String playerId, {
    required String pin,
    String? currentPin,
  }) => _repository.setPin(playerId, pin: pin, currentPin: currentPin);
}
