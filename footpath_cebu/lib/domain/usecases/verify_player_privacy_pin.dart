import 'package:footpath_cebu/domain/repositories/player_privacy_pin_repository.dart';

class VerifyPlayerPrivacyPin {
  const VerifyPlayerPrivacyPin(this._repository);

  final PlayerPrivacyPinRepository _repository;

  Future<String> call(String playerId, String pin) =>
      _repository.verifyPin(playerId, pin);
}
