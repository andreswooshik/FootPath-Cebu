import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';

void main() {
  group('AgeTier', () {
    test('wire values round-trip through fromWire', () {
      for (final tier in AgeTier.values) {
        expect(AgeTierInfo.fromWire(tier.wire), tier);
      }
    });

    test('unknown wire value falls back to development', () {
      expect(AgeTierInfo.fromWire('ELITE'), AgeTier.development);
    });

    test('tiers match the Capstone spec bounds', () {
      expect(AgeTier.foundation.ageRange, (min: 10, max: 12));
      expect(AgeTier.development.ageRange, (min: 13, max: 15));
      expect(AgeTier.pathway.ageRange, (min: 16, max: 18));
    });

    test('forAge maps each in-range age to exactly one tier', () {
      for (var age = 10; age <= 18; age++) {
        final matches = AgeTier.values.where((t) => t.includesAge(age));
        expect(matches.length, 1, reason: 'age $age matched ${matches.length}');
        expect(AgeTierInfo.forAge(age), matches.single);
      }
    });

    test('forAge returns null outside every tier', () {
      expect(AgeTierInfo.forAge(9), isNull);
      expect(AgeTierInfo.forAge(19), isNull);
    });

    test('ageLabel reads as the programme spec', () {
      expect(AgeTier.foundation.ageLabel, 'Ages 10–12');
    });
  });
}
