import 'package:footpath_cebu/domain/entities/player.dart';

/// One transition in a player's academic eligibility history — an append-only
/// audit entry recorded server-side whenever the status changes. Immutable
/// Model — no UI, no I/O.
///
/// Only statuses travel on the wire, never grades. [changedBy] is already
/// privacy-shaped by the server: families receive the acting *role* ("School
/// Staff"), staff receive the individual's name.
class EligibilityChange {
  const EligibilityChange({
    required this.id,
    required this.oldStatus,
    required this.newStatus,
    required this.changedAt,
    required this.changedBy,
  });

  final String id;

  /// Null for a record whose prior status was never captured (the backend
  /// sends an empty string for "no previous value").
  final EligibilityStatus? oldStatus;
  final EligibilityStatus newStatus;
  final DateTime changedAt;

  /// Who made the change, as the server chose to expose it — a display name
  /// for staff viewers, a role label for families, "System" when unknown.
  final String changedBy;

  factory EligibilityChange.fromJson(Map<String, dynamic> json) {
    final rawOld = json['oldStatus'] as String? ?? '';
    return EligibilityChange(
      id: json['id'].toString(),
      oldStatus:
          rawOld.isEmpty ? null : EligibilityStatusLabel.fromWire(rawOld),
      newStatus: EligibilityStatusLabel.fromWire(
        json['newStatus'] as String? ?? '',
      ),
      changedAt: DateTime.parse(json['changedAt'] as String),
      changedBy: json['changedBy'] as String? ?? 'System',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'oldStatus': oldStatus?.wire ?? '',
        'newStatus': newStatus.wire,
        'changedAt': changedAt.toIso8601String(),
        'changedBy': changedBy,
      };
}
