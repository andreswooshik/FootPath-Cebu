import 'package:footpath_cebu/domain/entities/player_privacy_pin.dart';

abstract class PlayerPrivacyPinRepository {
  Future<PlayerPrivacyPinStatus> fetchStatus(String playerId);

  Future<PlayerPrivacyPinStatus> setPin(
    String playerId, {
    required String pin,
    String? currentPin,
  });

  Future<void> verifyPin(String playerId, String pin);

  Future<PlayerPrivacyPinStatus> resetPin(String playerId);
}

class PlayerPrivacyPinException implements Exception {
  const PlayerPrivacyPinException(this.message);

  final String message;

  @override
  String toString() => message;
}
