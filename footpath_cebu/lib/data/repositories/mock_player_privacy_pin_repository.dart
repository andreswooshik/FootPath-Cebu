import 'package:footpath_cebu/domain/entities/player_privacy_pin.dart';
import 'package:footpath_cebu/domain/repositories/player_privacy_pin_repository.dart';

class MockPlayerPrivacyPinRepository implements PlayerPrivacyPinRepository {
  final Map<String, String> _pins = {};

  @override
  Future<PlayerPrivacyPinStatus> fetchStatus(String playerId) async =>
      PlayerPrivacyPinStatus(
        hasPin: _pins.containsKey(playerId),
        locked: false,
      );

  @override
  Future<PlayerPrivacyPinStatus> setPin(
    String playerId, {
    required String pin,
    String? currentPin,
  }) async {
    if (_pins.containsKey(playerId) && _pins[playerId] != currentPin) {
      throw const PlayerPrivacyPinException('The current PIN is incorrect.');
    }
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      throw const PlayerPrivacyPinException('PIN must contain 4 to 6 digits.');
    }
    _pins[playerId] = pin;
    final status = await fetchStatus(playerId);
    return PlayerPrivacyPinStatus(
      hasPin: status.hasPin,
      locked: status.locked,
      unlockToken: 'mock-unlock-$playerId',
    );
  }

  @override
  Future<String> verifyPin(String playerId, String pin) async {
    if (_pins[playerId] != pin) {
      throw const PlayerPrivacyPinException('The PIN is incorrect.');
    }
    return 'mock-unlock-$playerId';
  }

  @override
  Future<PlayerPrivacyPinStatus> resetPin(String playerId) async {
    _pins.remove(playerId);
    return fetchStatus(playerId);
  }
}
