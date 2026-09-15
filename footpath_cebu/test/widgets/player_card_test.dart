import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/development_assessment.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/domain/entities/player_stats.dart';
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

Player _statsAssessedGoalkeeper() => _goalkeeper().copyWith(
  currentPlayerStats: CurrentPlayerStats(
    catalogVersion: 1,
    position: 'GK',
    roleGroup: 'GOALKEEPER',
    attributes: const [
      'Diving',
      'Handling',
      'Kicking',
      'Reflexes',
      'Speed',
      'Positioning',
    ],
    scores: const {
      'diving': 79,
      'handling': 76,
      'kicking': 74,
      'reflexes': 91,
      'speed': 69,
      'positioning': 84,
    },
    overall: 79,
    assessedAt: DateTime(2026, 9, 16),
  ),
);

Player _withLatestStats(
  Player player, {
  required String roleGroup,
  required List<String> attributes,
  required Map<String, int> scores,
}) => player.copyWith(
  latestPlayerStats: LatestPlayerStats(
    catalog: PlayerStatsCatalog(
      version: 1,
      position: player.position!.wire,
      roleGroup: roleGroup,
      attributes: attributes,
    ),
    assessment: PlayerStatsAssessment(
      id: 'stats-${player.id}',
      position: player.position!.wire,
      roleGroup: roleGroup,
      catalogVersion: 1,
      scores: scores,
      overall: (scores.values.reduce((a, b) => a + b) / 6).round(),
      reason: 'MONTHLY_REVIEW',
      coachNotes: 'Current assessment.',
      createdAt: DateTime(2026, 9, 1),
    ),
  ),
);

Player _outfieldWithStats() => _withLatestStats(
  _outfield(),
  roleGroup: 'ATTACKER',
  attributes: const [
    'Pace',
    'Shooting',
    'Dribbling',
    'Off-ball Movement',
    'Passing',
    'Physical',
  ],
  scores: const {
    'pace': 88,
    'shooting': 84,
    'dribbling': 81,
    'off_ball_movement': 79,
    'passing': 76,
    'physical': 74,
  },
);

Player _goalkeeperWithStats() => _withLatestStats(
  _goalkeeper(),
  roleGroup: 'GOALKEEPER',
  attributes: const [
    'Diving',
    'Handling',
    'Kicking',
    'Reflexes',
    'Speed',
    'Positioning',
  ],
  scores: const {
    'diving': 89,
    'handling': 86,
    'kicking': 72,
    'reflexes': 93,
    'speed': 64,
    'positioning': 87,
  },
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
  double width = 300,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: width * 850 / 600,
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
      expect(find.text('PLAYER STATS · 0–99'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Test Striker, Striker (ST), Player Stats not assessed',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('view-profile-p1')));
      expect(tapped, isTrue);
      semantics.dispose();
    });

    testWidgets('keeps the profile action usable on a compact phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                height: 340,
                child: PlayerCard(player: _outfield(), onTap: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PlayerCard));
      await tester.pumpAndSettle();

      final action = find.byKey(const ValueKey('view-profile-p1'));
      expect(action, findsOneWidget);
      expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(action).width, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
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

    testWidgets('does not fall back to stale legacy profile ratings', (
      tester,
    ) async {
      await _pump(tester, _outfield());

      await tester.tap(find.byType(PlayerCard));
      await tester.pumpAndSettle();

      expect(find.text('PLAYER STATS · 0–99'), findsOneWidget);
      expect(find.text('NO PLAYER STATS ASSESSMENT'), findsOneWidget);
      for (final value in ['91', '82', '73', '64', '55', '46']) {
        expect(find.text(value), findsNothing);
      }
      expect(
        find.byKey(const ValueKey('player-attribute-overall')),
        findsNothing,
      );
      expect(find.text('Pathway'), findsNothing);
    });

    testWidgets('shows the latest position-aware outfield assessment', (
      tester,
    ) async {
      await _pump(tester, _outfieldWithStats());

      await tester.tap(find.byType(PlayerCard));
      await tester.pumpAndSettle();

      expect(find.text('PLAYER STATS · OVR 80'), findsOneWidget);
      for (final code in ['PAC', 'SHO', 'DRI', 'OFF', 'PAS', 'PHY']) {
        expect(find.text(code), findsOneWidget);
      }
      for (final value in ['88', '84', '81', '79', '76', '74']) {
        expect(find.text(value), findsOneWidget);
      }
      final overall = tester.widget<Text>(
        find.byKey(const ValueKey('player-attribute-overall')),
      );
      expect(overall.data, '80');
    });

    testWidgets('uses the latest goalkeeper Player Stats catalog', (
      tester,
    ) async {
      await _pump(tester, _goalkeeperWithStats());

      await tester.tap(find.byType(PlayerCard));
      await tester.pumpAndSettle();

      expect(find.text('PLAYER STATS · OVR 82'), findsOneWidget);
      for (final code in ['DIV', 'HAN', 'KIC', 'REF', 'SPD', 'POS']) {
        expect(find.text(code), findsOneWidget);
      }
      for (final value in ['89', '86', '72', '93', '64', '87']) {
        expect(find.text(value), findsOneWidget);
      }
      for (final code in ['PAC', 'SHO', 'PAS', 'DRI', 'DEF', 'PHY']) {
        expect(find.text(code), findsNothing);
      }
      final overall = tester.widget<Text>(
        find.byKey(const ValueKey('player-attribute-overall')),
      );
      expect(overall.data, '82');
    });

    testWidgets(
      'uses the latest Player Stats assessment on the attributes side',
      (tester) async {
        await _pump(tester, _statsAssessedGoalkeeper());

        await tester.tap(find.byType(PlayerCard));
        await tester.pumpAndSettle();

        for (final value in ['76', '74', '91', '69', '84']) {
          expect(find.text(value), findsOneWidget);
        }
        expect(find.text('79'), findsNWidgets(2));
        final overall = tester.widget<Text>(
          find.byKey(const ValueKey('player-attribute-overall')),
        );
        expect(overall.data, '79');
        expect(find.text('88'), findsNothing);
        expect(find.text('85'), findsNothing);
      },
    );

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

    testWidgets('keeps card labels readable at narrow mobile widths', (
      tester,
    ) async {
      await _pump(tester, _assessedPlayer(), width: 240);

      final heading = tester.widget<Text>(
        find.text('ASSESSMENT DOMAINS · 1–5'),
      );
      final domainLabel = tester.widget<Text>(find.text('TEC'));
      final playerName = tester.widget<Text>(find.text('Assessed Player'));

      expect(heading.style?.fontSize, greaterThanOrEqualTo(11));
      expect(domainLabel.style?.fontSize, greaterThanOrEqualTo(11));
      expect(playerName.style?.fontSize, greaterThanOrEqualTo(15));
      expect(tester.takeException(), isNull);
    });
  });
}
