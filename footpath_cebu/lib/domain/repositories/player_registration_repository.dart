import 'package:footpath_cebu/domain/entities/player_registration.dart';

abstract class PlayerRegistrationRepository {
  Future<void> checkGuardian(GuardianRegistrationData guardian);
  Future<PlayerRegistrationResult> register(PlayerRegistrationDraft draft);
}

class PlayerRegistrationException implements Exception {
  const PlayerRegistrationException(
    this.message, {
    this.existingGuardianId,
    this.uncertain = false,
  });
  final String message;
  final String? existingGuardianId;
  final bool uncertain;
  @override
  String toString() => message;
}
