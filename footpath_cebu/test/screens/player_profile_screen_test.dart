import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/screens/player_profile_screen.dart';
import 'package:footpath_cebu/presentation/widgets/attribute_radar_chart.dart';

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
  group('PlayerProfileScreen attribute tiles', () {
    testWidgets('an outfield player shows the outfield six tiles', (
      tester,
    ) async {
      await _pump(tester, _outfield());

      for (final code in ['PAC', 'SHO', 'PAS', 'DRI', 'DEF', 'PHY']) {
        expect(find.text(code), findsWidgets);
      }
      for (final code in ['DIV', 'HAN', 'KIC', 'REF', 'SPD', 'POS']) {
        expect(find.text(code), findsNothing);
      }
      // Radar chart wired to the outfield branch.
      expect(
        tester
            .widget<AttributeRadarChart>(find.byType(AttributeRadarChart))
            .isGoalkeeper,
        isFalse,
      );
      expect(find.byKey(const Key('upload-player-photo')), findsOneWidget);
    });

    testWidgets('a goalkeeper shows the GK six tiles, not the outfield six', (
      tester,
    ) async {
      await _pump(tester, _goalkeeper());

      for (final code in ['DIV', 'HAN', 'KIC', 'REF', 'SPD', 'POS']) {
        expect(find.text(code), findsWidgets);
      }
      for (final code in ['PAC', 'SHO', 'PAS', 'DRI', 'DEF', 'PHY']) {
        expect(find.text(code), findsNothing);
      }
      // Radar chart wired to the GK branch.
      expect(
        tester
            .widget<AttributeRadarChart>(find.byType(AttributeRadarChart))
            .isGoalkeeper,
        isTrue,
      );
    });
  });
}
