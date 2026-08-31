import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/development_assessment.dart';
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

Player _independentClubPlayer() => const Player(
  id: 'p9',
  name: 'Club Player',
  age: 16,
  classYear: 'Class of 2026',
  ageTier: AgeTier.pathway,
  position: PlayerPosition.striker,
  eligibility: EligibilityStatus.pending,
  academicEligibilityApplicable: false,
  ratings: PlayerRatings(
    pace: 70,
    shooting: 70,
    passing: 70,
    dribbling: 70,
    defending: 70,
    physical: 70,
  ),
);

Player _assessedPlayer() => Player(
  id: 'p10',
  name: 'Assessed Player',
  age: 15,
  classYear: 'Class of 2027',
  ageTier: AgeTier.development,
  position: PlayerPosition.centralMidfielder,
  eligibility: EligibilityStatus.eligible,
  ratings: const PlayerRatings(
    pace: 0,
    shooting: 0,
    passing: 0,
    dribbling: 0,
    defending: 0,
    physical: 0,
  ),
  developmentAssessment: CurrentDevelopmentAssessment(
    frameworkVersion: 1,
    ratings: DevelopmentScores(const {}),
    domainScores: const {
      'technical': 4,
      'tactical': 3.5,
      'physical': 3,
      'mental': 4.5,
      'socialValues': 5,
    },
    strengths: 'Scans before receiving.',
    developmentTargets: 'Use the weaker foot.',
    assessedAt: DateTime(2026, 8, 30),
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
  group('FUT-style PlayerCard development panel', () {
    testWidgets('flips before exposing the coach profile action', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var tapped = false;

      await _pump(tester, _outfield(), onTap: () => tapped = true);

      final card = find.bySemanticsLabel(
        'Test Striker, Striker (ST), assessment side, not assessed yet',
      );
      expect(card, findsOneWidget);
      await tester.tap(card);
      await tester.pumpAndSettle();

      expect(tapped, isFalse);
      expect(find.text('OUTFIELD ATTRIBUTES · 0–99'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Test Striker, Striker (ST), outfield attributes shown',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('view-profile-p1')));
      expect(tapped, isTrue);
      semantics.dispose();
    });

    testWidgets('omits eligibility for an independent-club player', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, _independentClubPlayer());

      expect(find.text('Pending'), findsNothing);
      expect(find.text('Eligibility N/A'), findsNothing);
      expect(
        find.bySemanticsLabel(
          'Club Player, Striker (ST), assessment side, not assessed yet',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('does not present legacy ratings as current development data', (
      tester,
    ) async {
      await _pump(tester, _goalkeeper());

      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.text('AWAITING ASSESSMENT'), findsOneWidget);
      expect(find.text('Pathway'), findsNothing);
      for (final code in [
        'PAC',
        'SHO',
        'PAS',
        'DRI',
        'DEF',
        'DIV',
        'HAN',
        'KIC',
        'REF',
        'SPD',
        'POS',
      ]) {
        expect(find.text(code), findsNothing);
      }
    });

    testWidgets('flips to all six outfield legacy attributes', (tester) async {
      await _pump(tester, _outfield());

      await tester.tap(find.byType(PlayerCard));
      await tester.pumpAndSettle();

      expect(find.text('OUTFIELD ATTRIBUTES · 0–99'), findsOneWidget);
      for (final code in ['PAC', 'SHO', 'PAS', 'DRI', 'DEF', 'PHY']) {
        expect(find.text(code), findsOneWidget);
      }
      for (final value in ['91', '82', '73', '64', '55', '46']) {
        expect(find.text(value), findsOneWidget);
      }
      expect(find.text('${_outfield().overall}'), findsNothing);
      expect(find.text('Pathway'), findsNothing);
    });

    testWidgets('uses the goalkeeper-specific six on the legacy side', (
      tester,
    ) async {
      await _pump(tester, _goalkeeper());

      await tester.tap(find.byType(PlayerCard));
      await tester.pumpAndSettle();

      expect(find.text('GOALKEEPER ATTRIBUTES · 0–99'), findsOneWidget);
      for (final code in ['DIV', 'HAN', 'KIC', 'REF', 'SPD', 'POS']) {
        expect(find.text(code), findsOneWidget);
      }
      for (final value in ['88', '85', '70', '92', '62', '86']) {
        expect(find.text(value), findsOneWidget);
      }
      for (final code in ['PAC', 'SHO', 'PAS', 'DRI', 'DEF', 'PHY']) {
        expect(find.text(code), findsNothing);
      }
      expect(find.text('${_goalkeeper().overall}'), findsNothing);
    });

    testWidgets('shows five independent development domains without overall', (
      tester,
    ) async {
      await _pump(tester, _assessedPlayer());

      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.text('ASSESSMENT DOMAINS · 1–5'), findsOneWidget);
      expect(find.text('Development'), findsNothing);
      for (final label in ['TEC', 'TAC', 'PHYS', 'MEN', 'VAL']) {
        expect(find.text(label), findsOneWidget);
      }
      for (final value in ['4.0', '3.5', '3.0', '4.5', '5.0']) {
        expect(find.text(value), findsOneWidget);
      }
      expect(find.textContaining('overall'), findsNothing);
    });
  });
}
