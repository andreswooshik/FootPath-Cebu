import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';

void main() {
  group('PlayerRatings', () {
    test('overall is the rounded average of the six attributes', () {
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
        position: 'ST',
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
  });
}
