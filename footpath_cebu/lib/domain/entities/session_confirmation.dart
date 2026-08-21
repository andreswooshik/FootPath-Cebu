/// Whether a player intends to attend a scheduled session — set by the
/// player themselves, before the session happens. Distinct from
/// [Attendance], which the coach records during/after the session.
enum ConfirmationStatus { confirmed, declined }

extension ConfirmationStatusLabel on ConfirmationStatus {
  String get wire => name.toUpperCase();

  String get label {
    switch (this) {
      case ConfirmationStatus.confirmed:
        return 'Confirmed';
      case ConfirmationStatus.declined:
        return 'Declined';
    }
  }

  static ConfirmationStatus fromWire(String value) {
    return ConfirmationStatus.values.firstWhere(
      (s) => s.wire == value.toUpperCase(),
      orElse: () => ConfirmationStatus.declined,
    );
  }
}

/// One player's RSVP for one training session.
class SessionConfirmation {
  const SessionConfirmation({
    required this.sessionId,
    required this.playerId,
    required this.status,
    required this.respondedAt,
  });

  final String sessionId;
  final String playerId;
  final ConfirmationStatus status;
  final DateTime respondedAt;

  factory SessionConfirmation.fromJson(Map<String, dynamic> json) {
    return SessionConfirmation(
      sessionId: json['sessionId'].toString(),
      playerId: json['playerId'].toString(),
      status: ConfirmationStatusLabel.fromWire(
        json['status'] as String? ?? 'DECLINED',
      ),
      respondedAt: DateTime.parse(json['respondedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'playerId': playerId,
    'status': status.wire,
    'respondedAt': respondedAt.toIso8601String(),
  };
}
