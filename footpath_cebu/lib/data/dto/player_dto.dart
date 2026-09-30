import 'package:footpath_cebu/data/dto/player_stats_dto.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/development_assessment.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/domain/entities/player.dart';

abstract final class PlayerRatingsDto {
  static PlayerRatings fromJson(Map<String, dynamic> json) {
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
}

abstract final class PlayerDto {
  static Player fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'].toString(),
      name: json['name'] as String? ?? '',
      age: json['age'] as int? ?? 0,
      classYear: json['classYear'] as String? ?? '',
      ageTier: AgeTierInfo.fromWire(json['ageTier'] as String? ?? ''),
      position: PlayerPositionInfo.fromWire(json['position'] as String?),
      ratings: PlayerRatingsDto.fromJson(
        (json['ratings'] as Map<String, dynamic>?) ?? const {},
      ),
      eligibility: EligibilityStatusLabel.fromWire(
        json['eligibility'] as String? ?? 'PENDING',
      ),
      academicEligibilityApplicable:
          json['academicEligibilityApplicable'] as bool? ?? true,
      photoUrl: json['photoUrl'] as String?,
      coachNotes: json['coachNotes'] as String? ?? '',
      developmentAssessment:
          json['developmentAssessment'] is Map<String, dynamic>
          ? CurrentDevelopmentAssessment.fromJson(
              json['developmentAssessment'] as Map<String, dynamic>,
            )
          : null,
      currentPlayerStats: json['currentPlayerStats'] is Map<String, dynamic>
          ? CurrentPlayerStatsDto.fromJson(
              Map<String, dynamic>.from(json['currentPlayerStats'] as Map),
            )
          : null,
      latestPlayerStats: json['latestPlayerStats'] is Map
          ? LatestPlayerStatsDto.fromJson(
              Map<String, dynamic>.from(json['latestPlayerStats'] as Map),
            )
          : null,
    );
  }
}

extension PlayerRatingsJson on PlayerRatings {
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

extension PlayerJson on Player {
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
    'developmentAssessment': developmentAssessment == null
        ? null
        : {
            'frameworkVersion': developmentAssessment!.frameworkVersion,
            'ratings': developmentAssessment!.ratings.toJson(),
            'domainScores': developmentAssessment!.domainScores,
            'strengths': developmentAssessment!.strengths,
            'developmentTargets': developmentAssessment!.developmentTargets,
            'assessedAt': developmentAssessment!.assessedAt?.toIso8601String(),
          },
    'currentPlayerStats': currentPlayerStats?.toJson(),
    'latestPlayerStats': latestPlayerStats?.toJson(),
  };
}
