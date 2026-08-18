import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';

void main() {
  group('PlayerRatings', () {
    test('overall is the rounded average of the six outfield attributes', () {
      const ratings = PlayerRatings(
        pace: 90,
        shooting: 90,
        passing: 90,
        dribbling: 90,
        defending: 60,
        physical: 60,
      );
      // (90*4 + 60*2) / 6 = 80
      expect(ratings.overall, 80);
    });

    test('gkOverall is the rounded average of the six GK attributes', () {
      const ratings = PlayerRatings(
        // Outfield six left at their defaults — gkOverall must not read them.
        pace: 0,
        shooting: 0,
        passing: 0,
        dribbling: 0,
        defending: 0,
        physical: 0,
        diving: 90,
        handling: 90,
        kicking: 90,
        reflexes: 90,
        speed: 60,
        positioning: 60,
      );
      // (90*4 + 60*2) / 6 = 80
      expect(ratings.gkOverall, 80);
    });
  });

  group('Player.overall — position-aware', () {
    test('a goalkeeper is judged on the GK six, not the outfield six', () {
      const player = Player(
        id: 'gk1',
        name: 'Test Keeper',
        age: 17,
        classYear: 'Class of 2025',
        ageTier: AgeTier.pathway,
        position: PlayerPosition.goalkeeper,
        eligibility: EligibilityStatus.eligible,
        ratings: PlayerRatings(
          // Deliberately poor outfield six — must be ignored for a keeper.
          pace: 1,
          shooting: 1,
          passing: 1,
          dribbling: 1,
          defending: 1,
          physical: 1,
          diving: 85,
          handling: 82,
          kicking: 70,
          reflexes: 90,
          speed: 60,
          positioning: 88,
        ),
      );
      // (85+82+70+90+60+88) / 6 = 79.166... -> 79
      expect(player.overall, 79);
      expect(player.overall, player.ratings.gkOverall);
    });

    test('an outfield player is judged on the outfield six, not the GK six', () {
      const player = Player(
        id: 'st1',
        name: 'Test Striker',
        age: 17,
        classYear: 'Class of 2025',
        ageTier: AgeTier.pathway,
        position: PlayerPosition.striker,
        eligibility: EligibilityStatus.eligible,
        ratings: PlayerRatings(
          pace: 90,
          shooting: 90,
          passing: 90,
          dribbling: 90,
          defending: 60,
          physical: 60,
          // Deliberately high GK six — must be ignored for an outfield player.
          diving: 99,
          handling: 99,
          kicking: 99,
          reflexes: 99,
          speed: 99,
          positioning: 99,
        ),
      );
      expect(player.overall, 80);
      expect(player.overall, player.ratings.overall);
    });

    test('an unassigned player (position == null) uses the outfield six', () {
      const player = Player(
        id: 'unassigned1',
        name: 'Test Unassigned',
        age: 12,
        classYear: 'Class of 2030',
        ageTier: AgeTier.foundation,
        position: null,
        eligibility: EligibilityStatus.pending,
        ratings: PlayerRatings(
          pace: 90,
          shooting: 90,
          passing: 90,
          dribbling: 90,
          defending: 60,
          physical: 60,
          diving: 99,
          handling: 99,
          kicking: 99,
          reflexes: 99,
          speed: 99,
          positioning: 99,
        ),
      );
      expect(player.overall, 80);
    });
  });

  group('EligibilityStatus', () {
    test('wire values round-trip through fromWire', () {
      for (final status in EligibilityStatus.values) {
        expect(EligibilityStatusLabel.fromWire(status.wire), status);
      }
    });

    test('unknown wire value falls back to pending', () {
      expect(
        EligibilityStatusLabel.fromWire('SOMETHING_ELSE'),
        EligibilityStatus.pending,
      );
    });
  });

  group('Player JSON', () {
    test('fromJson/toJson round-trips', () {
      const player = Player(
        id: 'p1',
        name: 'Rhobert Ronaldo',
        age: 16,
        classYear: 'Class of 2026',
        ageTier: AgeTier.pathway,
        position: PlayerPosition.striker,
        eligibility: EligibilityStatus.eligible,
        ratings: PlayerRatings(
          pace: 99,
          shooting: 97,
          passing: 88,
          dribbling: 95,
          defending: 45,
          physical: 90,
        ),
      );

      final restored = Player.fromJson(player.toJson());

      expect(restored.id, player.id);
      expect(restored.name, player.name);
      expect(restored.age, player.age);
      expect(restored.position, player.position);
      expect(restored.ageTier, player.ageTier);
      expect(restored.eligibility, player.eligibility);
      expect(restored.overall, player.overall);
    });

    test('fromJson tolerates missing optional fields', () {
      final player = Player.fromJson({'id': 7, 'name': 'Test'});
      expect(player.id, '7');
      expect(player.eligibility, EligibilityStatus.pending);
      expect(player.ageTier, AgeTier.development);
      expect(player.overall, 0);
    });

    test('independent-club eligibility applicability round-trips as false', () {
      final player = Player.fromJson({
        'id': 8,
        'name': 'Independent Player',
        'academicEligibilityApplicable': false,
      });
      expect(player.academicEligibilityApplicable, isFalse);
      expect(player.toJson()['academicEligibilityApplicable'], isFalse);
    });

    test('a goalkeeper\'s GK six round-trips through JSON', () {
      const player = Player(
        id: 'gk1',
        name: 'Test Keeper',
        age: 17,
        classYear: 'Class of 2025',
        ageTier: AgeTier.pathway,
        position: PlayerPosition.goalkeeper,
        eligibility: EligibilityStatus.eligible,
        ratings: PlayerRatings(
          pace: 55,
          shooting: 22,
          passing: 74,
          dribbling: 60,
          defending: 48,
          physical: 88,
          diving: 88,
          handling: 85,
          kicking: 70,
          reflexes: 92,
          speed: 62,
          positioning: 86,
        ),
      );

      final restored = Player.fromJson(player.toJson());

      // Field-level checks, not just overall: two independently-wrong values
      // could coincidentally still average to the same overall.
      expect(restored.ratings.diving, player.ratings.diving);
      expect(restored.ratings.handling, player.ratings.handling);
      expect(restored.ratings.kicking, player.ratings.kicking);
      expect(restored.ratings.reflexes, player.ratings.reflexes);
      expect(restored.ratings.speed, player.ratings.speed);
      expect(restored.ratings.positioning, player.ratings.positioning);
      expect(restored.overall, player.overall);
    });
  });
}
