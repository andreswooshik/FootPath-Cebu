/// Injury status values. Kept as an enum so the UI never deals with raw
/// strings and invalid states are unrepresentable.
enum InjuryStatus { active, recovering, recovered }

enum InjuryType { muscle, jointLigament, bone, headFace, other }

enum InjurySeverity { minor, moderate, severe }

enum InjuryReportStatus { pending, confirmed, rejected, archived }

enum InjuryUpdateReviewStatus { pending, approved, rejected }

extension InjuryTypeWire on InjuryType {
  String get wire => switch (this) {
    InjuryType.jointLigament => 'JOINT_LIGAMENT',
    InjuryType.headFace => 'HEAD_FACE',
    _ => name.toUpperCase(),
  };

  String get label => switch (this) {
    InjuryType.muscle => 'Muscle',
    InjuryType.jointLigament => 'Joint / ligament',
    InjuryType.bone => 'Bone',
    InjuryType.headFace => 'Head / face',
    InjuryType.other => 'Other',
  };

  static InjuryType fromWire(String? value) => switch (value?.toUpperCase()) {
    'MUSCLE' => InjuryType.muscle,
    'JOINT_LIGAMENT' => InjuryType.jointLigament,
    'BONE' => InjuryType.bone,
    'HEAD_FACE' => InjuryType.headFace,
    _ => InjuryType.other,
  };
}

extension InjurySeverityWire on InjurySeverity {
  String get wire => name.toUpperCase();

  String get label => switch (this) {
    InjurySeverity.minor => 'Minor',
    InjurySeverity.moderate => 'Moderate',
    InjurySeverity.severe => 'Severe',
  };

  String get guidance => switch (this) {
    InjurySeverity.minor => 'Discomfort with little impact on normal movement',
    InjurySeverity.moderate => 'Limits training or requires modified activity',
    InjurySeverity.severe => 'Unable to continue or needs urgent assessment',
  };

  static InjurySeverity fromWire(String? value) =>
      switch (value?.toUpperCase()) {
        'MINOR' => InjurySeverity.minor,
        'SEVERE' => InjurySeverity.severe,
        _ => InjurySeverity.moderate,
      };
}

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

extension InjuryReportStatusWire on InjuryReportStatus {
  String get wire => name.toUpperCase();

  String get label => switch (this) {
    InjuryReportStatus.pending => 'Pending confirmation',
    InjuryReportStatus.confirmed => 'Confirmed',
    InjuryReportStatus.rejected => 'Rejected',
    InjuryReportStatus.archived => 'Archived',
  };

  static InjuryReportStatus fromWire(String? value) =>
      switch (value?.toUpperCase()) {
        'PENDING' => InjuryReportStatus.pending,
        'REJECTED' => InjuryReportStatus.rejected,
        'ARCHIVED' => InjuryReportStatus.archived,
        _ => InjuryReportStatus.confirmed,
      };
}

extension InjuryUpdateReviewStatusWire on InjuryUpdateReviewStatus {
  String get wire => name.toUpperCase();

  static InjuryUpdateReviewStatus fromWire(String? value) =>
      switch (value?.toUpperCase()) {
        'APPROVED' => InjuryUpdateReviewStatus.approved,
        'REJECTED' => InjuryUpdateReviewStatus.rejected,
        _ => InjuryUpdateReviewStatus.pending,
      };
}

class InjuryStatusUpdate {
  const InjuryStatusUpdate({
    required this.id,
    required this.proposedStatus,
    required this.reviewStatus,
    required this.submittedByName,
    required this.submittedByRole,
    required this.createdAt,
    this.proposedResolvedOn,
    this.notes,
    this.rejectionReason,
  });

  final String id;
  final InjuryStatus proposedStatus;
  final DateTime? proposedResolvedOn;
  final String? notes;
  final InjuryUpdateReviewStatus reviewStatus;
  final String submittedByName;
  final String submittedByRole;
  final String? rejectionReason;
  final DateTime createdAt;

  factory InjuryStatusUpdate.fromJson(Map<String, dynamic> json) =>
      InjuryStatusUpdate(
        id: json['id'].toString(),
        proposedStatus: InjuryStatusWire.fromWire(
          json['proposedStatus'] as String,
        ),
        proposedResolvedOn: json['proposedResolvedOn'] == null
            ? null
            : DateTime.parse(json['proposedResolvedOn'] as String),
        notes: InjuryRecord.blankAsNull(json['notes'] as String?),
        reviewStatus: InjuryUpdateReviewStatusWire.fromWire(
          json['reviewStatus'] as String?,
        ),
        submittedByName: json['submittedByName'] as String? ?? 'Care team',
        submittedByRole: json['submittedByRole'] as String? ?? '',
        rejectionReason: InjuryRecord.blankAsNull(
          json['rejectionReason'] as String?,
        ),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class InjuryPlayerOption {
  const InjuryPlayerOption({
    required this.id,
    required this.name,
    required this.ageTier,
  });

  final String id;
  final String name;
  final String ageTier;

  factory InjuryPlayerOption.fromJson(Map<String, dynamic> json) =>
      InjuryPlayerOption(
        id: json['id'].toString(),
        name: json['name'] as String? ?? '',
        ageTier: json['ageTier'] as String? ?? '',
      );
}

class InjuryStatusUpdateDraft {
  const InjuryStatusUpdateDraft({
    required this.proposedStatus,
    this.proposedResolvedOn,
    this.notes,
  });

  final InjuryStatus proposedStatus;
  final DateTime? proposedResolvedOn;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'proposedStatus': proposedStatus.wire,
    'proposedResolvedOn': proposedResolvedOn == null
        ? null
        : InjuryRecord.dateOnly(proposedResolvedOn!),
    'notes': notes ?? '',
  };
}

/// One private injury report shared with the player's club care team.
///
/// The server supplies workflow capabilities so each role only sees actions
/// it can perform: reporters manage Pending reports, while the Coordinator
/// confirms, rejects, updates, and archives the official record.
class InjuryRecord {
  const InjuryRecord({
    this.id,
    required this.playerId,
    required this.description,
    required this.status,
    required this.occurredOn,
    this.injuryType = InjuryType.other,
    this.severity = InjurySeverity.moderate,
    this.bodyPart,
    this.resolvedOn,
    this.notes,
    this.playerName = '',
    this.reviewStatus = InjuryReportStatus.confirmed,
    this.reporterName = '',
    this.reporterRole = '',
    this.rejectionReason,
    this.reviewedAt,
    this.archivedAt,
    this.pendingStatusUpdate,
    this.canEditPending = false,
    this.canReview = false,
    this.canEditConfirmed = false,
    this.canArchive = false,
    this.canRequestStatusUpdate = false,
    this.createdAt,
    this.updatedAt,
  });

  /// Server-assigned identifier; null for a record not yet saved.
  final String? id;
  final String playerId;
  final String playerName;

  /// What happened, e.g. "Sprained ankle".
  final String description;
  final InjuryType injuryType;
  final InjurySeverity severity;
  final InjuryStatus status;

  /// The day of the injury (date-only on the wire: yyyy-MM-dd).
  final DateTime occurredOn;

  /// Where, e.g. "Left ankle". Optional.
  final String? bodyPart;

  /// When the player was cleared; null while the injury is open.
  final DateTime? resolvedOn;

  /// Free-form context (how it happened, treatment, restrictions).
  final String? notes;
  final InjuryReportStatus reviewStatus;
  final String reporterName;
  final String reporterRole;
  final String? rejectionReason;
  final DateTime? reviewedAt;
  final DateTime? archivedAt;
  final InjuryStatusUpdate? pendingStatusUpdate;
  final bool canEditPending;
  final bool canReview;
  final bool canEditConfirmed;
  final bool canArchive;
  final bool canRequestStatusUpdate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  InjuryRecord copyWith({
    String? description,
    InjuryType? injuryType,
    InjurySeverity? severity,
    InjuryStatus? status,
    DateTime? occurredOn,
    String? bodyPart,
    DateTime? resolvedOn,
    String? notes,
    bool clearBodyPart = false,
    bool clearResolvedOn = false,
    bool clearNotes = false,
  }) {
    return InjuryRecord(
      id: id,
      playerId: playerId,
      description: description ?? this.description,
      injuryType: injuryType ?? this.injuryType,
      severity: severity ?? this.severity,
      status: status ?? this.status,
      occurredOn: occurredOn ?? this.occurredOn,
      bodyPart: clearBodyPart ? null : (bodyPart ?? this.bodyPart),
      resolvedOn: clearResolvedOn ? null : (resolvedOn ?? this.resolvedOn),
      notes: clearNotes ? null : (notes ?? this.notes),
      playerName: playerName,
      reviewStatus: reviewStatus,
      reporterName: reporterName,
      reporterRole: reporterRole,
      rejectionReason: rejectionReason,
      reviewedAt: reviewedAt,
      archivedAt: archivedAt,
      pendingStatusUpdate: pendingStatusUpdate,
      canEditPending: canEditPending,
      canReview: canReview,
      canEditConfirmed: canEditConfirmed,
      canArchive: canArchive,
      canRequestStatusUpdate: canRequestStatusUpdate,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory InjuryRecord.fromJson(Map<String, dynamic> json) {
    return InjuryRecord(
      id: json['id']?.toString(),
      playerId: json['playerId'] as String,
      playerName: json['playerName'] as String? ?? '',
      description: json['description'] as String,
      injuryType: InjuryTypeWire.fromWire(json['injuryType'] as String?),
      severity: InjurySeverityWire.fromWire(json['severity'] as String?),
      status: InjuryStatusWire.fromWire(json['status'] as String),
      occurredOn: DateTime.parse(json['occurredOn'] as String),
      bodyPart: _blankAsNull(json['bodyPart'] as String?),
      resolvedOn: json['resolvedOn'] == null
          ? null
          : DateTime.parse(json['resolvedOn'] as String),
      notes: _blankAsNull(json['notes'] as String?),
      reviewStatus: InjuryReportStatusWire.fromWire(
        json['reviewStatus'] as String?,
      ),
      reporterName: json['reporterName'] as String? ?? '',
      reporterRole: json['reporterRole'] as String? ?? '',
      rejectionReason: _blankAsNull(json['rejectionReason'] as String?),
      reviewedAt: json['reviewedAt'] == null
          ? null
          : DateTime.parse(json['reviewedAt'] as String),
      archivedAt: json['archivedAt'] == null
          ? null
          : DateTime.parse(json['archivedAt'] as String),
      pendingStatusUpdate: json['pendingStatusUpdate'] is Map<String, dynamic>
          ? InjuryStatusUpdate.fromJson(
              json['pendingStatusUpdate'] as Map<String, dynamic>,
            )
          : null,
      canEditPending: json['canEditPending'] as bool? ?? false,
      canReview: json['canReview'] as bool? ?? false,
      canEditConfirmed: json['canEditConfirmed'] as bool? ?? false,
      canArchive: json['canArchive'] as bool? ?? false,
      canRequestStatusUpdate: json['canRequestStatusUpdate'] as bool? ?? false,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// Write shape for POST/PUT — dates are date-only and the server still
  /// validates whether the authenticated reporter may target [playerId].
  Map<String, dynamic> toJson() => {
    'playerId': playerId,
    'description': description,
    'injuryType': injuryType.wire,
    'severity': severity.wire,
    'status': status.wire,
    'occurredOn': _dateOnly(occurredOn),
    'bodyPart': bodyPart ?? '',
    'resolvedOn': resolvedOn == null ? null : _dateOnly(resolvedOn!),
    'notes': notes ?? '',
  };

  static String _dateOnly(DateTime date) =>
      date.toIso8601String().split('T').first;

  static String dateOnly(DateTime date) => _dateOnly(date);

  /// The backend stores optional text as '', the app models it as null.
  static String? _blankAsNull(String? value) =>
      (value == null || value.isEmpty) ? null : value;

  static String? blankAsNull(String? value) => _blankAsNull(value);
}
