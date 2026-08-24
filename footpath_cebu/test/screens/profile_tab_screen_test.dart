import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:footpath_cebu/domain/entities/age_tier.dart';
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

Player _goalkeeper() => const Player(
  id: 'p7',
  name: 'Test Keeper',
  age: 16,
  classYear: 'Class of 2026',
  ageTier: AgeTier.pathway,
  position: PlayerPosition.goalkeeper,
  eligibility: EligibilityStatus.notEligible,
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

Future<void> _pump(WidgetTester tester, Player player) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(home: ProfileTabScreen(player: player)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ProfileTabScreen attributes', () {
    testWidgets('a player can choose their own profile photo', (tester) async {
      await _pump(tester, _outfield());

      expect(find.byKey(const Key('upload-own-player-photo')), findsOneWidget);
    });

    testWidgets('an outfield player sees full-word outfield labels', (
      tester,
    ) async {
      await _pump(tester, _outfield());

      for (final label in [
        'Pace',
        'Shooting',
        'Passing',
        'Dribbling',
        'Defending',
        'Physical',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      for (final label in [
        'Diving',
        'Handling',
        'Kicking',
        'Reflexes',
        'Speed',
        'Positioning',
      ]) {
        expect(find.text(label), findsNothing);
      }
    });

    testWidgets('a goalkeeper sees full-word GK labels, not outfield labels', (
      tester,
    ) async {
      await _pump(tester, _goalkeeper());

      for (final label in [
        'Diving',
        'Handling',
        'Kicking',
        'Reflexes',
        'Speed',
        'Positioning',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      for (final label in [
        'Pace',
        'Shooting',
        'Passing',
        'Dribbling',
        'Defending',
        'Physical',
      ]) {
        expect(find.text(label), findsNothing);
      }
    });
  });
}
