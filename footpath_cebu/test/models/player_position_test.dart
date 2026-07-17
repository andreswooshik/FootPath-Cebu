import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';

Player _player({PlayerPosition? position}) => Player(
      id: 'p1',
      name: 'Reiner Neymar',
      age: 15,
      classYear: 'Class of 2027',
      ageTier: AgeTier.development,
      position: position,
      eligibility: EligibilityStatus.eligible,
      ratings: const PlayerRatings(
        pace: 80, shooting: 80, passing: 80, dribbling: 80, defending: 80,
        physical: 80,
      ),
    );

void main() {
  group('PlayerPosition', () {
    test('covers the ten positions in the spec', () {
      expect(
        PlayerPosition.values.map((p) => p.code),
        ['GK', 'CB', 'LB', 'RB', 'CDM', 'CM', 'CAM', 'LW', 'RW', 'ST'],
      );
    });

    test('wire values round-trip through fromWire', () {
      for (final position in PlayerPosition.values) {
        expect(PlayerPositionInfo.fromWire(position.wire), position);
      }
    });

    test('fromWire is case-insensitive', () {
      expect(PlayerPositionInfo.fromWire('st'), PlayerPosition.striker);
    });

    test('an absent or unknown wire value reads as unassigned, not a guess',
        () {
      expect(PlayerPositionInfo.fromWire(null), isNull);
      expect(PlayerPositionInfo.fromWire(''), isNull);
      expect(PlayerPositionInfo.fromWire('SWEEPER'), isNull);
    });

    test('every position belongs to exactly one group', () {
      final grouped = [
        for (final g in PositionGroup.values) ...PlayerPositionInfo.inGroup(g),
      ];
      expect(grouped.toSet(), PlayerPosition.values.toSet());
      expect(grouped.length, PlayerPosition.values.length);
    });

    test('groups hold the expected lines', () {
      expect(
        PlayerPositionInfo.inGroup(PositionGroup.defence).map((p) => p.code),
        ['CB', 'LB', 'RB'],
      );
      expect(
        PlayerPositionInfo.inGroup(PositionGroup.attack).map((p) => p.code),
        ['LW', 'RW', 'ST'],
      );
    });

    test('labelWithCode reads as the UI shows it', () {
      expect(PlayerPosition.striker.labelWithCode, 'Striker (ST)');
    });
  });

  group('Player.position', () {
    test('is null when the admin registered the player without one', () {
      expect(_player().position, isNull);
    });

    test('an unassigned player round-trips through JSON as unassigned', () {
      final restored = Player.fromJson(_player().toJson());
      expect(restored.position, isNull);
    });

    test('an assigned position round-trips through JSON', () {
      final restored =
          Player.fromJson(_player(position: PlayerPosition.striker).toJson());
      expect(restored.position, PlayerPosition.striker);
    });

    test('toJson writes the short code', () {
      expect(_player(position: PlayerPosition.leftWinger).toJson()['position'],
          'LW');
      expect(_player().toJson()['position'], isNull);
    });

    test('copyWith assigns a position to an unassigned player', () {
      final assigned = _player().copyWith(position: PlayerPosition.striker);
      expect(assigned.position, PlayerPosition.striker);
    });

    test('copyWith leaves the position alone when not passed', () {
      final same = _player(position: PlayerPosition.striker)
          .copyWith(eligibility: EligibilityStatus.pending);
      expect(same.position, PlayerPosition.striker);
    });
  });
}
