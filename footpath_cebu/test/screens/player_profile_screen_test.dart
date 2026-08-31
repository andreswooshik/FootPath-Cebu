import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/development_assessment.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/screens/player_profile_screen.dart';

const _coach = UserProfile(
  id: 'c1',
  email: 'coach@example.com',
  firstName: 'Ralf',
  lastName: 'Cruz',
  role: 'COACH',
  roleDisplay: 'Coach',
);

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
  coachNotes: 'Keeps responding to feedback.',
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
  await tester.binding.setSurfaceSize(const Size(600, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: PlayerProfileScreen(player: player, profile: _coach),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('PlayerProfileScreen development assessment', () {
    testWidgets('keeps legacy ratings out of the active profile', (
      tester,
    ) async {
      await _pump(tester, _outfield());

      for (final code in [
        'PAC',
        'SHO',
        'PAS',
        'DRI',
        'DEF',
        'PHY',
        'DIV',
        'HAN',
        'KIC',
        'REF',
        'SPD',
        'POS',
      ]) {
        expect(find.text(code), findsNothing);
      }
      expect(find.text('No development assessment yet'), findsWidgets);
      expect(find.text('Development feedback'), findsOneWidget);
      expect(find.byKey(const Key('upload-player-photo')), findsOneWidget);
      expect(find.text('Create Development Assessment'), findsOneWidget);
    });

    testWidgets('shows the five domains, strength, target, and notes', (
      tester,
    ) async {
      await _pump(tester, _assessedPlayer());

      for (final label in [
        'Technical',
        'Tactical',
        'Physical',
        'Mental',
        'Values',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Observed strength'), findsOneWidget);
      expect(find.text('Scans before receiving.'), findsOneWidget);
      expect(find.text('Next development target'), findsOneWidget);
      expect(find.text('Use the weaker foot under pressure.'), findsOneWidget);
      expect(find.text('Keeps responding to feedback.'), findsOneWidget);
    });
  });
}
