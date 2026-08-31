import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/development_assessment.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/presentation/screens/profile_tab_screen.dart';

Player _outfield() => const Player(
  id: 'p3',
  name: 'Test Winger',
  age: 15,
  classYear: 'Class of 2027',
  ageTier: AgeTier.development,
  position: PlayerPosition.leftWinger,
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

Player _assessedPlayer() => _outfield().copyWith(
  coachNotes: 'Good response to feedback.',
  developmentAssessment: CurrentDevelopmentAssessment(
    frameworkVersion: 1,
    ratings: DevelopmentScores(const {}),
    domainScores: const {
      'technical': 4,
      'tactical': 3.5,
      'physical': 3,
      'mental': 4,
      'socialValues': 5,
    },
    strengths: 'Scans before receiving.',
    developmentTargets: 'Use the weaker foot under pressure.',
    assessedAt: DateTime(2026, 8, 30),
  ),
);

Future<void> _pump(WidgetTester tester, Player player) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(home: ProfileTabScreen(player: player)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ProfileTabScreen development assessment', () {
    testWidgets('a player can choose their own profile photo', (tester) async {
      await _pump(tester, _outfield());

      expect(find.byKey(const Key('upload-own-player-photo')), findsOneWidget);
    });

    testWidgets('shows an honest empty state instead of legacy ratings', (
      tester,
    ) async {
      await _pump(tester, _outfield());

      expect(find.text('Development assessment'), findsOneWidget);
      expect(
        find.textContaining('No development assessment yet'),
        findsOneWidget,
      );
      expect(find.text('Pace'), findsNothing);
      expect(find.text('Diving'), findsNothing);
    });

    testWidgets('shows five domains with strength, target, and coach notes', (
      tester,
    ) async {
      await _pump(tester, _assessedPlayer());

      for (final label in [
        'Technical',
        'Tactical',
        'Physical',
        'Mental',
        'Social / Values',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Observed strength'), findsOneWidget);
      expect(find.text('Scans before receiving.'), findsOneWidget);
      expect(find.text('Next development target'), findsOneWidget);
      expect(find.text('Use the weaker foot under pressure.'), findsOneWidget);
      expect(find.text('Additional coach notes'), findsOneWidget);
      expect(find.text('Good response to feedback.'), findsOneWidget);
    });
  });
}
