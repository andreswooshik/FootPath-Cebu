import 'package:footpath_cebu/domain/entities/age_tier.dart';

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
    required this.position,
    required this.ratings,
    required this.eligibility,
    this.photoUrl,
  });

  final String id;
  final String name;
  final int age;

  /// Graduating cohort, e.g. "Class of 2025".
  final String classYear;

  /// Age tier the player is registered under. Stored rather than derived from
  /// [age] — see [AgeTierInfo.forAge].
  final AgeTier ageTier;

  /// Field position abbreviation, e.g. ST, CM, GK.
  final String position;

  final PlayerRatings ratings;
  final EligibilityStatus eligibility;
  final String? photoUrl;

  int get overall => ratings.overall;

  /// Returns a copy with selected fields replaced — used by the coach's
  /// assessment form to apply edited ratings without mutating the original.
  Player copyWith({PlayerRatings? ratings, EligibilityStatus? eligibility}) {
    return Player(
      id: id,
      name: name,
      age: age,
      classYear: classYear,
      ageTier: ageTier,
      position: position,
      ratings: ratings ?? this.ratings,
      eligibility: eligibility ?? this.eligibility,
      photoUrl: photoUrl,
    );
  }

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'].toString(),
      name: json['name'] as String? ?? '',
      age: json['age'] as int? ?? 0,
      classYear: json['classYear'] as String? ?? '',
      ageTier: AgeTierInfo.fromWire(json['ageTier'] as String? ?? ''),
      position: json['position'] as String? ?? '',
      ratings: PlayerRatings.fromJson(
        (json['ratings'] as Map<String, dynamic>?) ?? const {},
      ),
      eligibility: EligibilityStatusLabel.fromWire(
        json['eligibility'] as String? ?? 'PENDING',
      ),
      photoUrl: json['photoUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'age': age,
        'classYear': classYear,
        'ageTier': ageTier.wire,
        'position': position,
        'ratings': ratings.toJson(),
        'eligibility': eligibility.wire,
        'photoUrl': photoUrl,
      };
}
