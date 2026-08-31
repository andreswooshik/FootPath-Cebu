import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/development_assessment.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/presentation/widgets/mini_player_card.dart';

Player _player({required bool eligibilityApplies}) => Player(
  id: 'p1',
  name: 'Test Player',
  age: 16,
  classYear: 'Class of 2026',
  ageTier: AgeTier.pathway,
  position: PlayerPosition.striker,
  eligibility: EligibilityStatus.pending,
  academicEligibilityApplicable: eligibilityApplies,
  ratings: const PlayerRatings(
    pace: 70,
    shooting: 70,
    passing: 70,
    dribbling: 70,
    defending: 70,
    physical: 70,
  ),
);

Player _assessedPlayer() => _player(eligibilityApplies: true).copyWith(
  developmentAssessment: CurrentDevelopmentAssessment(
    frameworkVersion: 1,
    ratings: DevelopmentScores(const {}),
    domainScores: const {'technical': 4},
    strengths: 'Scans early.',
    developmentTargets: 'Use the weaker foot.',
    assessedAt: DateTime(2026, 8, 30),
  ),
);

Future<void> _pump(WidgetTester tester, Player player) async {
  await tester.binding.setSurfaceSize(const Size(360, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: MiniPlayerCard(player: player)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the eligibility marker for a school-club player', (
    tester,
  ) async {
    await _pump(tester, _player(eligibilityApplies: true));

    expect(find.byKey(const Key('mini-player-eligibility')), findsOneWidget);
    expect(find.textContaining('Awaiting assessment'), findsOneWidget);
  });

  testWidgets('omits the eligibility marker for an independent-club player', (
    tester,
  ) async {
    await _pump(tester, _player(eligibilityApplies: false));

    expect(find.byKey(const Key('mini-player-eligibility')), findsNothing);
  });

  testWidgets('shows five-domain completion without a combined score', (
    tester,
  ) async {
    await _pump(tester, _assessedPlayer());

    expect(find.textContaining('5 domains assessed'), findsOneWidget);
    expect(find.textContaining('overall'), findsNothing);
  });
}
