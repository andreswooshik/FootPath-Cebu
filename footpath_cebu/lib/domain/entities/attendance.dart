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
    this.sessionId,
    this.sessionName,
    this.coachUid,
    this.effort,
    this.performanceScore,
    this.note,
    this.sessionFocus,
    this.sessionDate,
  });

  final String playerId;
  final AttendanceStatus status;

  /// When the record was last set — used as the session date in read views.
  final DateTime updatedAt;

  /// The training session this record belongs to. Required to tell two
  /// same-named sessions apart; [sessionName] alone cannot.
  final String? sessionId;

  /// The training session this attendance belongs to, e.g. "Evening Training".
  /// Optional: coach-side writes may not carry it.
  final String? sessionName;
  final String? coachUid;

  /// Effort/intensity the coach observed, 0-100. Session-scoped and only
  /// meaningful when [status] is present — it describes one day, unlike the
  /// player's long-lived [PlayerRatings].
  final int? effort;

  /// Quality of the player's training performance, 0.0-10.0. This is not an
  /// effort score: a player can work hard while execution quality is lower.
  final double? performanceScore;

  /// The coach's short remark about this player on this day.
  final String? note;
  final String? sessionFocus;
  final DateTime? sessionDate;

  Attendance copyWith({
    AttendanceStatus? status,
    DateTime? updatedAt,
    String? sessionId,
    String? sessionName,
    int? effort,
    double? performanceScore,
    String? note,
    bool clearParticipationValues = false,
    bool clearPerformanceScore = false,
  }) {
    return Attendance(
      playerId: playerId,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
      sessionId: sessionId ?? this.sessionId,
      sessionName: sessionName ?? this.sessionName,
      coachUid: coachUid,
      effort: clearParticipationValues ? null : effort ?? this.effort,
      performanceScore: clearParticipationValues
          ? null
          : clearPerformanceScore
          ? null
          : performanceScore ?? this.performanceScore,
      note: note ?? this.note,
      sessionFocus: sessionFocus,
      sessionDate: sessionDate,
    );
  }

  factory Attendance.fromJson(Map<String, dynamic> json) {
    return Attendance(
      playerId: json['playerId'] as String,
      status: AttendanceStatusWire.fromWire(json['status'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      sessionId: json['sessionId']?.toString(),
      sessionName: json['sessionName'] as String?,
      coachUid: json['coachUid'] as String?,
      effort: json['effort'] as int?,
      performanceScore: _asNullableDouble(json['performanceScore']),
      note: json['note'] as String?,
      sessionFocus: json['sessionFocus'] as String?,
      sessionDate: json['sessionDate'] == null
          ? null
          : DateTime.parse(json['sessionDate'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'playerId': playerId,
    'status': status.wire,
    'updatedAt': updatedAt.toIso8601String(),
    if (sessionId != null) 'sessionId': sessionId,
    if (sessionName != null) 'sessionName': sessionName,
    if (coachUid != null) 'coachUid': coachUid,
    if (effort != null) 'effort': effort,
    if (performanceScore != null) 'performanceScore': performanceScore,
    if (note != null) 'note': note,
  };
}

double? _asNullableDouble(dynamic value) => switch (value) {
  num number => number.toDouble(),
  String text => double.tryParse(text),
  _ => null,
};
