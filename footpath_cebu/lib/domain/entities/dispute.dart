/// Dispute categories a coach can flag under. Enum so the UI never deals with
/// raw strings and invalid states are unrepresentable.
enum DisputeCategory { attendance, assessment, eligibility, conduct, other }

extension DisputeCategoryInfo on DisputeCategory {
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
}

/// Lifecycle of a dispute ticket.
enum DisputeStatus { open, underReview, resolved, dismissed }

extension DisputeStatusInfo on DisputeStatus {
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
}
