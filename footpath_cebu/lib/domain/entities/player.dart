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

/// The six standardized attributes shown on the player's FUT-style card,
/// plus an optional goalkeeper six used only when the player is a keeper.
///
/// A single flat class rather than two subtypes: every [Player] — outfield or
/// keeper — carries one [PlayerRatings], and the six that actually apply are
/// chosen by [Player.overall] and the position-aware UI, not by this class.
/// [PlayerRatings] itself stays position-unaware; see [overall] vs [gkOverall].
class PlayerRatings {
  const PlayerRatings({
    required this.pace,
    required this.shooting,
    required this.passing,
    required this.dribbling,
    required this.defending,
    required this.physical,
    this.diving = 0,
    this.handling = 0,
    this.kicking = 0,
    this.reflexes = 0,
    this.speed = 0,
    this.positioning = 0,
  });

  final int pace;
  final int shooting;
  final int passing;
  final int dribbling;
  final int defending;
  final int physical;

  /// Goalkeeper attribute — shot-stopping on the ground and in the air.
  final int diving;

  /// Goalkeeper attribute — catching and holding crosses/shots.
  final int handling;

  /// Goalkeeper attribute — distribution with the ball at their feet.
  final int kicking;

  /// Goalkeeper attribute — reaction speed on close-range shots.
  final int reflexes;

  /// Goalkeeper attribute — mobility off the line. Distinct from the outfield
  /// [pace]: a keeper's speed is judged on sweeping and closing angles, not
  /// sprinting the length of the pitch.
  final int speed;

  /// Goalkeeper attribute — reading the game and starting position.
  final int positioning;

  /// Overall for an outfield player — the big number on the card corner.
  /// Ignores the GK six; see [gkOverall] for the goalkeeper equivalent and
  /// [Player.overall] for which one actually gets shown.
  int get overall =>
      ((pace + shooting + passing + dribbling + defending + physical) / 6)
          .round();

  /// Overall for a goalkeeper — the same corner number, computed from the GK
  /// six instead. Ignores the outfield six.
  int get gkOverall =>
      ((diving + handling + kicking + reflexes + speed + positioning) / 6)
          .round();

  factory PlayerRatings.fromJson(Map<String, dynamic> json) {
    return PlayerRatings(
      pace: json['pace'] as int? ?? 0,
      shooting: json['shooting'] as int? ?? 0,
      passing: json['passing'] as int? ?? 0,
      dribbling: json['dribbling'] as int? ?? 0,
      defending: json['defending'] as int? ?? 0,
      physical: json['physical'] as int? ?? 0,
      diving: json['diving'] as int? ?? 0,
      handling: json['handling'] as int? ?? 0,
      kicking: json['kicking'] as int? ?? 0,
      reflexes: json['reflexes'] as int? ?? 0,
      speed: json['speed'] as int? ?? 0,
      positioning: json['positioning'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'pace': pace,
    'shooting': shooting,
    'passing': passing,
    'dribbling': dribbling,
    'defending': defending,
    'physical': physical,
    'diving': diving,
    'handling': handling,
    'kicking': kicking,
    'reflexes': reflexes,
    'speed': speed,
    'positioning': positioning,
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
    this.academicEligibilityApplicable = true,
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

  /// Applicability is separate from the four allowed status values. An
  /// Independent club reports false and the UI displays N/A without inventing
  /// a fifth stored eligibility status.
  final bool academicEligibilityApplicable;
  final String? photoUrl;

  /// The coach's standing written evaluation, saved with the assessment.
  ///
  /// Empty when no coach has written one yet — never null, so the UI can test
  /// `isNotEmpty` without a null check. Distinct from the per-session remarks
  /// on [Attendance], which are a running commentary rather than a current
  /// summary.
  final String coachNotes;

  /// The overall rating shown on the card corner.
  ///
  /// Goalkeepers are judged on the GK six (diving/handling/kicking/reflexes/
  /// speed/positioning); every other position — and an unassigned player,
  /// preserving prior behaviour — uses the outfield six. [CardTier] thresholds
  /// apply identically to either number: it consumes [overall] without caring
  /// which six produced it.
  int get overall => position?.group == PositionGroup.goalkeeper
      ? ratings.gkOverall
      : ratings.overall;

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
      academicEligibilityApplicable: academicEligibilityApplicable,
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
      academicEligibilityApplicable:
          json['academicEligibilityApplicable'] as bool? ?? true,
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
    'academicEligibilityApplicable': academicEligibilityApplicable,
    'photoUrl': photoUrl,
    'coachNotes': coachNotes,
  };
}
