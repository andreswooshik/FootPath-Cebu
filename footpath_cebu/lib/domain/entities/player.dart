import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';

/// Academic eligibility, mirroring the backend enum. Never stores grades —
/// only the gating status set by School Staff.
enum EligibilityStatus { eligible, notEligible, pending, academicWarning }

extension EligibilityStatusLabel on EligibilityStatus {
  /// Wire value used by the backend (ELIGIBLE / NOT_ELIGIBLE / ...).
  String get wire {
    switch (this) {
      case EligibilityStatus.eligible:
        return 'ELIGIBLE';
      case EligibilityStatus.notEligible:
        return 'NOT_ELIGIBLE';
      case EligibilityStatus.pending:
        return 'PENDING';
      case EligibilityStatus.academicWarning:
        return 'ACADEMIC_WARNING';
    }
  }

  /// Short label shown on the roster card.
  String get label {
    switch (this) {
      case EligibilityStatus.eligible:
        return 'Eligible';
      case EligibilityStatus.notEligible:
        return 'Not Eligible';
      case EligibilityStatus.pending:
        return 'Pending';
      case EligibilityStatus.academicWarning:
        return 'Academic Warning';
    }
  }

  static EligibilityStatus fromWire(String value) {
    return EligibilityStatus.values.firstWhere(
      (s) => s.wire == value.toUpperCase(),
      orElse: () => EligibilityStatus.pending,
    );
  }
}

/// The six standardized attributes shown on the player's FUT-style card.
class PlayerRatings {
  const PlayerRatings({
    required this.pace,
    required this.shooting,
    required this.passing,
    required this.dribbling,
    required this.defending,
    required this.physical,
  });

  final int pace;
  final int shooting;
  final int passing;
  final int dribbling;
  final int defending;
  final int physical;

  /// Overall rating — the big number on the card corner.
  int get overall =>
      ((pace + shooting + passing + dribbling + defending + physical) / 6)
          .round();

  factory PlayerRatings.fromJson(Map<String, dynamic> json) {
    return PlayerRatings(
      pace: json['pace'] as int? ?? 0,
      shooting: json['shooting'] as int? ?? 0,
      passing: json['passing'] as int? ?? 0,
      dribbling: json['dribbling'] as int? ?? 0,
      defending: json['defending'] as int? ?? 0,
      physical: json['physical'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'pace': pace,
        'shooting': shooting,
        'passing': passing,
        'dribbling': dribbling,
        'defending': defending,
        'physical': physical,
      };
}

/// A player in the coach's squad roster. Immutable Model — no UI, no I/O.
class Player {
  const Player({
    required this.id,
    required this.name,
    required this.age,
    required this.classYear,
    required this.ageTier,
    this.position,
    required this.ratings,
    required this.eligibility,
    this.photoUrl,
    this.coachNotes = '',
  });

  final String id;
  final String name;
  final int age;

  /// Graduating cohort, e.g. "Class of 2025".
  final String classYear;

  /// Age tier the player is registered under. Stored rather than derived from
  /// [age] — see [AgeTierInfo.forAge].
  final AgeTier ageTier;

  /// The player's position, or null when the coach hasn't assigned one yet.
  ///
  /// Null by design: the admin registers a player without a position, and the
  /// coach sets it after evaluating them.
  final PlayerPosition? position;

  final PlayerRatings ratings;
  final EligibilityStatus eligibility;
  final String? photoUrl;

  /// The coach's standing written evaluation, saved with the assessment.
  ///
  /// Empty when no coach has written one yet — never null, so the UI can test
  /// `isNotEmpty` without a null check. Distinct from the per-session remarks
  /// on [Attendance], which are a running commentary rather than a current
  /// summary.
  final String coachNotes;

  int get overall => ratings.overall;

  /// Returns a copy with selected fields replaced — used by the coach's
  /// assessment form to apply edited ratings, and by the position picker.
  ///
  /// Note that a null argument means "leave unchanged", so this cannot clear
  /// [position] back to unassigned. That's deliberate: a coach assigns or
  /// changes a position, never un-assigns one.
  Player copyWith({
    PlayerRatings? ratings,
    EligibilityStatus? eligibility,
    PlayerPosition? position,
    String? coachNotes,
  }) {
    return Player(
      id: id,
      name: name,
      age: age,
      classYear: classYear,
      ageTier: ageTier,
      position: position ?? this.position,
      ratings: ratings ?? this.ratings,
      eligibility: eligibility ?? this.eligibility,
      photoUrl: photoUrl,
      coachNotes: coachNotes ?? this.coachNotes,
    );
  }

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'].toString(),
      name: json['name'] as String? ?? '',
      age: json['age'] as int? ?? 0,
      classYear: json['classYear'] as String? ?? '',
      ageTier: AgeTierInfo.fromWire(json['ageTier'] as String? ?? ''),
      position: PlayerPositionInfo.fromWire(json['position'] as String?),
      ratings: PlayerRatings.fromJson(
        (json['ratings'] as Map<String, dynamic>?) ?? const {},
      ),
      eligibility: EligibilityStatusLabel.fromWire(
        json['eligibility'] as String? ?? 'PENDING',
      ),
      photoUrl: json['photoUrl'] as String?,
      coachNotes: json['coachNotes'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'age': age,
        'classYear': classYear,
        'ageTier': ageTier.wire,
        'position': position?.wire,
        'ratings': ratings.toJson(),
        'eligibility': eligibility.wire,
        'photoUrl': photoUrl,
        'coachNotes': coachNotes,
      };
}
