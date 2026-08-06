/// The server-side state of a player's household privacy PIN.
class PlayerPrivacyPinStatus {
  const PlayerPrivacyPinStatus({
    required this.hasPin,
    required this.locked,
    this.lockedUntil,
  });

  final bool hasPin;
  final bool locked;
  final DateTime? lockedUntil;

  factory PlayerPrivacyPinStatus.fromJson(Map<String, dynamic> json) {
    final raw = json['lockedUntil'];
    return PlayerPrivacyPinStatus(
      hasPin: json['hasPin'] == true,
      locked: json['locked'] == true,
      lockedUntil: raw is String ? DateTime.tryParse(raw) : null,
    );
  }
}
