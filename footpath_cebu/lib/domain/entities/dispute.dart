/// Dispute categories a coach can flag under. Enum so the UI never deals with
/// raw strings and invalid states are unrepresentable.
enum DisputeCategory { attendance, assessment, eligibility, conduct, other }

extension DisputeCategoryWire on DisputeCategory {
  /// Uppercase wire format used by the backend.
  String get wire => name.toUpperCase();

  String get label {
    switch (this) {
      case DisputeCategory.attendance:
        return 'Attendance';
      case DisputeCategory.assessment:
        return 'Assessment';
      case DisputeCategory.eligibility:
        return 'Eligibility';
      case DisputeCategory.conduct:
        return 'Conduct';
      case DisputeCategory.other:
        return 'Other';
    }
  }

  static DisputeCategory fromWire(String value) {
    return DisputeCategory.values.firstWhere(
      (c) => c.wire == value.toUpperCase(),
      orElse: () => DisputeCategory.other,
    );
  }
}

/// Lifecycle of a dispute ticket.
enum DisputeStatus { open, underReview, resolved, dismissed }

extension DisputeStatusWire on DisputeStatus {
  /// Uppercase snake-case wire format (UNDER_REVIEW etc.).
  String get wire {
    switch (this) {
      case DisputeStatus.open:
        return 'OPEN';
      case DisputeStatus.underReview:
        return 'UNDER_REVIEW';
      case DisputeStatus.resolved:
        return 'RESOLVED';
      case DisputeStatus.dismissed:
        return 'DISMISSED';
    }
  }

  String get label {
    switch (this) {
      case DisputeStatus.open:
        return 'Open';
      case DisputeStatus.underReview:
        return 'Under Review';
      case DisputeStatus.resolved:
        return 'Resolved';
      case DisputeStatus.dismissed:
        return 'Dismissed';
    }
  }

  static DisputeStatus fromWire(String value) {
    return DisputeStatus.values.firstWhere(
      (s) => s.wire == value.toUpperCase(),
      orElse: () => DisputeStatus.open,
    );
  }
}

/// One append-only entry in a dispute's thread — the audit trail.
class DisputeResponse {
  const DisputeResponse({
    required this.id,
    required this.body,
    required this.createdAt,
    this.authorName,
    this.authorRole,
    this.statusChangeTo,
  });

  final String id;
  final String body;
  final DateTime createdAt;
  final String? authorName;

  /// The author's wire role (COACH / SCHOOL_STAFF / ADMIN).
  final String? authorRole;

  /// The status this response moved the dispute to, when it did.
  final DisputeStatus? statusChangeTo;

  factory DisputeResponse.fromJson(Map<String, dynamic> json) {
    final statusChange = json['statusChangeTo'] as String?;
    return DisputeResponse(
      id: json['id'].toString(),
      body: json['body'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      authorName: json['authorName'] as String?,
      authorRole: json['authorRole'] as String?,
      statusChangeTo: statusChange == null
          ? null
          : DisputeStatusWire.fromWire(statusChange),
    );
  }
}

/// A flagged issue raised by a coach — a status ticket with an append-only
/// response thread. Plain immutable data class; no business logic.
class Dispute {
  const Dispute({
    required this.id,
    required this.category,
    required this.status,
    required this.summary,
    required this.createdAt,
    required this.updatedAt,
    this.detail,
    this.raisedByName,
    this.subjectPlayerId,
    this.subjectPlayerName,
    this.responses = const [],
  });

  final String id;
  final DisputeCategory category;
  final DisputeStatus status;
  final String summary;
  final String? detail;
  final String? raisedByName;

  /// The player the dispute concerns, when there is one.
  final String? subjectPlayerId;
  final String? subjectPlayerName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<DisputeResponse> responses;

  factory Dispute.fromJson(Map<String, dynamic> json) {
    return Dispute(
      id: json['id'].toString(),
      category: DisputeCategoryWire.fromWire(json['category'] as String),
      status: DisputeStatusWire.fromWire(json['status'] as String),
      summary: json['summary'] as String,
      detail: _blankAsNull(json['detail'] as String?),
      raisedByName: json['raisedByName'] as String?,
      subjectPlayerId: json['subjectPlayerId']?.toString(),
      subjectPlayerName: json['subjectPlayerName'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      responses: (json['responses'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(DisputeResponse.fromJson)
          .toList(),
    );
  }

  static String? _blankAsNull(String? value) =>
      (value == null || value.isEmpty) ? null : value;
}
