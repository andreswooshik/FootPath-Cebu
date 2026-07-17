/// Injury status values. Kept as an enum so the UI never deals with raw
/// strings and invalid states are unrepresentable.
enum InjuryStatus { active, recovering, recovered }

extension InjuryStatusWire on InjuryStatus {
  /// Uppercase wire format used by the backend (ACTIVE/RECOVERING/RECOVERED).
  String get wire => name.toUpperCase();

  /// Human-readable label shown in the UI.
  String get label {
    switch (this) {
      case InjuryStatus.active:
        return 'Active';
      case InjuryStatus.recovering:
        return 'Recovering';
      case InjuryStatus.recovered:
        return 'Recovered';
    }
  }

  static InjuryStatus fromWire(String value) {
    return InjuryStatus.values.firstWhere(
      (s) => s.wire == value.toUpperCase(),
      orElse: () => InjuryStatus.active,
    );
  }
}

/// One injury in a player's medical history.
///
/// Plain immutable data class (the "Model" in MVVM) — no business logic, no
/// knowledge of Firebase, HTTP, or widgets. Medical data: only the player
/// edits it, coach/admin read it, guardians never see it (server-enforced).
class InjuryRecord {
  const InjuryRecord({
    this.id,
    required this.playerId,
    required this.description,
    required this.status,
    required this.occurredOn,
    this.bodyPart,
    this.resolvedOn,
    this.notes,
  });

  /// Server-assigned identifier; null for a record not yet saved.
  final String? id;
  final String playerId;

  /// What happened, e.g. "Sprained ankle".
  final String description;
  final InjuryStatus status;

  /// The day of the injury (date-only on the wire: yyyy-MM-dd).
  final DateTime occurredOn;

  /// Where, e.g. "Left ankle". Optional.
  final String? bodyPart;

  /// When the player was cleared; null while the injury is open.
  final DateTime? resolvedOn;

  /// Free-form context (how it happened, treatment, restrictions).
  final String? notes;

  InjuryRecord copyWith({
    String? description,
    InjuryStatus? status,
    DateTime? occurredOn,
    String? bodyPart,
    DateTime? resolvedOn,
    String? notes,
  }) {
    return InjuryRecord(
      id: id,
      playerId: playerId,
      description: description ?? this.description,
      status: status ?? this.status,
      occurredOn: occurredOn ?? this.occurredOn,
      bodyPart: bodyPart ?? this.bodyPart,
      resolvedOn: resolvedOn ?? this.resolvedOn,
      notes: notes ?? this.notes,
    );
  }

  factory InjuryRecord.fromJson(Map<String, dynamic> json) {
    return InjuryRecord(
      id: json['id']?.toString(),
      playerId: json['playerId'] as String,
      description: json['description'] as String,
      status: InjuryStatusWire.fromWire(json['status'] as String),
      occurredOn: DateTime.parse(json['occurredOn'] as String),
      bodyPart: _blankAsNull(json['bodyPart'] as String?),
      resolvedOn: json['resolvedOn'] == null
          ? null
          : DateTime.parse(json['resolvedOn'] as String),
      notes: _blankAsNull(json['notes'] as String?),
    );
  }

  /// Write shape for POST/PUT — dates are date-only, server-owned fields
  /// (id, playerId, timestamps) are omitted.
  Map<String, dynamic> toJson() => {
        'description': description,
        'status': status.wire,
        'occurredOn': _dateOnly(occurredOn),
        'bodyPart': bodyPart ?? '',
        'resolvedOn': resolvedOn == null ? null : _dateOnly(resolvedOn!),
        'notes': notes ?? '',
      };

  static String _dateOnly(DateTime date) =>
      date.toIso8601String().split('T').first;

  /// The backend stores optional text as '', the app models it as null.
  static String? _blankAsNull(String? value) =>
      (value == null || value.isEmpty) ? null : value;
}
