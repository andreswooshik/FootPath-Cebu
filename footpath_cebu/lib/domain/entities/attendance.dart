/// Attendance status values. Kept as an enum so the UI never deals with raw
/// strings and invalid states are unrepresentable.
enum AttendanceStatus { present, absent, excused }

extension AttendanceStatusWire on AttendanceStatus {
  /// Uppercase wire format used by the backend (PRESENT/ABSENT/EXCUSED).
  String get wire => name.toUpperCase();

  /// Human-readable label shown in the UI (Present/Absent/Excused).
  String get label {
    switch (this) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.excused:
        return 'Excused';
    }
  }

  static AttendanceStatus fromWire(String value) {
    return AttendanceStatus.values.firstWhere(
      (s) => s.wire == value.toUpperCase(),
      orElse: () => AttendanceStatus.absent,
    );
  }
}

/// A single attendance record for one player on one training day.
///
/// This is a plain immutable data class (the "Model" in MVVM) — it holds no
/// business logic and knows nothing about Firebase, HTTP, or widgets.
class Attendance {
  const Attendance({
    required this.playerId,
    required this.status,
    required this.updatedAt,
    this.sessionName,
    this.coachUid,
  });

  final String playerId;
  final AttendanceStatus status;

  /// When the record was last set — used as the session date in read views.
  final DateTime updatedAt;

  /// The training session this attendance belongs to, e.g. "Evening Training".
  /// Optional: coach-side writes may not carry it.
  final String? sessionName;
  final String? coachUid;

  Attendance copyWith({
    AttendanceStatus? status,
    DateTime? updatedAt,
    String? sessionName,
  }) {
    return Attendance(
      playerId: playerId,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
      sessionName: sessionName ?? this.sessionName,
      coachUid: coachUid,
    );
  }

  factory Attendance.fromJson(Map<String, dynamic> json) {
    return Attendance(
      playerId: json['playerId'] as String,
      status: AttendanceStatusWire.fromWire(json['status'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      sessionName: json['sessionName'] as String?,
      coachUid: json['coachUid'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'status': status.wire,
        'updatedAt': updatedAt.toIso8601String(),
        if (sessionName != null) 'sessionName': sessionName,
        if (coachUid != null) 'coachUid': coachUid,
      };
}
