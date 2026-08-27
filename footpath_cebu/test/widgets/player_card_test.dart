import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/presentation/widgets/player_card.dart';

Player _outfield() => const Player(
  id: 'p1',
  name: 'Test Striker',
  age: 16,
  classYear: 'Class of 2026',
  ageTier: AgeTier.pathway,
  position: PlayerPosition.striker,
  eligibility: EligibilityStatus.eligible,
  ratings: PlayerRatings(
    pace: 91,
    shooting: 82,
    passing: 73,
    dribbling: 64,
    defending: 55,
    physical: 46,
  ),
);

Player _goalkeeper() => const Player(
  id: 'p7',
  name: 'Test Keeper',
  age: 16,
  classYear: 'Class of 2026',
  ageTier: AgeTier.pathway,
  position: PlayerPosition.goalkeeper,
  eligibility: EligibilityStatus.notEligible,
  // Deliberately poor outfield six — must never surface for a keeper.
  ratings: PlayerRatings(
    pace: 1,
    shooting: 1,
    passing: 1,
    dribbling: 1,
    defending: 1,
    physical: 1,
    diving: 88,
    handling: 85,
    kicking: 70,
    reflexes: 92,
    speed: 62,
    positioning: 86,
  ),
);

Future<void> _pump(
  WidgetTester tester,
  Player player, {
  VoidCallback? onTap,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 425,
            child: PlayerCard(player: player, onTap: onTap),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('PlayerCard stats panel', () {
    testWidgets('exposes a concise accessible action', (tester) async {
      final semantics = tester.ensureSemantics();
      var tapped = false;

      await _pump(tester, _outfield(), onTap: () => tapped = true);

      final card = find.bySemanticsLabel(
        'Test Striker, Striker (ST), Pathway, overall rating 69, Eligible',
      );
      expect(card, findsOneWidget);
      await tester.tap(card);
      expect(tapped, isTrue);
      semantics.dispose();
    });

    testWidgets('an outfield player shows the outfield six, not the GK six', (
      tester,
    ) async {
      final player = _outfield();
      await _pump(tester, player);

      final expected = {
        'PAC': player.ratings.pace,
        'SHO': player.ratings.shooting,
        'PAS': player.ratings.passing,
        'DRI': player.ratings.dribbling,
        'DEF': player.ratings.defending,
        'PHY': player.ratings.physical,
      };
      for (final entry in expected.entries) {
        expect(find.text(entry.key), findsWidgets);
        expect(find.text('${entry.value}'), findsOneWidget);
      }
      for (final code in ['DIV', 'HAN', 'KIC', 'REF', 'SPD', 'POS']) {
        expect(find.text(code), findsNothing);
      }
      // Corner badge shows the outfield overall.
      expect(find.text('${player.overall}'), findsOneWidget);
    });

    testWidgets('a goalkeeper shows the GK six, not the outfield six', (
      tester,
    ) async {
      final player = _goalkeeper();
      await _pump(tester, player);

      final expected = {
        'DIV': player.ratings.diving,
        'HAN': player.ratings.handling,
        'KIC': player.ratings.kicking,
        'REF': player.ratings.reflexes,
        'SPD': player.ratings.speed,
        'POS': player.ratings.positioning,
      };
      for (final entry in expected.entries) {
        expect(find.text(entry.key), findsWidgets);
        expect(find.text('${entry.value}'), findsOneWidget);
      }
      for (final code in ['PAC', 'SHO', 'PAS', 'DRI', 'DEF', 'PHY']) {
        expect(find.text(code), findsNothing);
      }
      // Corner badge shows gkOverall (81), never the deliberately-bad
      // outfield-six average.
      expect(player.overall, player.ratings.gkOverall);
      expect(find.text('${player.overall}'), findsOneWidget);
    });
  });
}
