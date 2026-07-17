import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
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

const _guardian = UserProfile(
  id: 'g1',
  email: 'parent@example.com',
  firstName: 'Ana',
  lastName: 'Reyes',
  role: 'GUARDIAN',
  roleDisplay: 'Guardian',
);

Player _player({PlayerPosition? position}) => Player(
      // p3 exists in the mock squad, so the save path resolves.
      id: 'p3',
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
  /// Scrolls the picker sheet to [label] and taps it. The attack line sits
  /// below the fold on a phone, so a coach flicks to reach Striker.
  Future<void> tapPosition(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(
      find.text(label),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> pump(
    WidgetTester tester, {
    PlayerPosition? position,
    UserProfile profile = _coach,
  }) async {
    await tester.binding.setSurfaceSize(const Size(600, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: PlayerProfileScreen(
            player: _player(position: position),
            profile: profile,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('viewing', () {
    testWidgets('shows the current position', (tester) async {
      await pump(tester, position: PlayerPosition.leftWinger);

      expect(find.text('Player Position'), findsOneWidget);
      expect(find.text('Left Winger (LW)'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Change'), findsOneWidget);
    });

    testWidgets('an unassigned player says so and offers Assign',
        (tester) async {
      await pump(tester);

      expect(find.text('Not yet assigned'), findsOneWidget);
      expect(
        find.text('The coach assigns this after evaluating the player.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Assign'), findsWidgets);
    });
  });

  group('role gate', () {
    testWidgets('a non-coach can view the position but not change it',
        (tester) async {
      await pump(
        tester,
        position: PlayerPosition.leftWinger,
        profile: _guardian,
      );

      // Still visible...
      expect(find.text('Left Winger (LW)'), findsOneWidget);
      // ...but with no way to act on it.
      expect(find.widgetWithText(TextButton, 'Change'), findsNothing);
    });

    testWidgets('a non-coach gets no Assign button on an unassigned player',
        (tester) async {
      await pump(tester, profile: _guardian);

      expect(find.text('Not yet assigned'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Assign'), findsNothing);
    });
  });

  group('picker', () {
    testWidgets('lists all ten positions grouped by line', (tester) async {
      await pump(tester, position: PlayerPosition.leftWinger);
      await tester.tap(find.widgetWithText(TextButton, 'Change'));
      await tester.pumpAndSettle();

      expect(find.text('Change Position'), findsOneWidget);
      expect(find.text('Reiner Neymar'), findsWidgets);

      // Every group and position is reachable by scrolling the sheet.
      for (final group in ['GOALKEEPER', 'DEFENCE', 'MIDFIELD', 'ATTACK']) {
        await tester.scrollUntilVisible(
          find.text(group),
          120,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text(group), findsOneWidget);
      }
      for (final position in PlayerPosition.values) {
        await tester.scrollUntilVisible(
          find.text(position.label),
          120,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text(position.label), findsOneWidget);
      }
    });

    testWidgets('an unassigned player gets the Assign wording',
        (tester) async {
      await pump(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Assign').first);
      await tester.pumpAndSettle();

      expect(find.text('Assign Position'), findsOneWidget);
    });
  });

  group('confirming', () {
    testWidgets('choosing a position confirms before saving', (tester) async {
      await pump(tester, position: PlayerPosition.leftWinger);
      await tester.tap(find.widgetWithText(TextButton, 'Change'));
      await tester.pumpAndSettle();
      await tapPosition(tester, 'Striker');

      expect(find.text('Change position?'), findsOneWidget);
      expect(
        find.text(
          'Reiner Neymar will change from Left Winger (LW) to Striker (ST).',
        ),
        findsOneWidget,
      );
    });

    testWidgets('cancelling leaves the position untouched', (tester) async {
      await pump(tester, position: PlayerPosition.leftWinger);
      await tester.tap(find.widgetWithText(TextButton, 'Change'));
      await tester.pumpAndSettle();
      await tapPosition(tester, 'Striker');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Left Winger (LW)'), findsOneWidget);
      expect(find.text('Striker (ST)'), findsNothing);
    });

    testWidgets('confirming saves and reports success', (tester) async {
      await pump(tester, position: PlayerPosition.leftWinger);
      await tester.tap(find.widgetWithText(TextButton, 'Change'));
      await tester.pumpAndSettle();
      await tapPosition(tester, 'Striker');
      await tester.tap(find.widgetWithText(FilledButton, 'Change'));
      await tester.pumpAndSettle();

      expect(find.text('Reiner Neymar is now Striker (ST).'), findsOneWidget);
      expect(find.text('Striker (ST)'), findsOneWidget);
    });

    testWidgets('assigning an unassigned player uses Assign wording',
        (tester) async {
      await pump(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Assign').first);
      await tester.pumpAndSettle();
      await tapPosition(tester, 'Goalkeeper');

      expect(find.text('Assign position?'), findsOneWidget);
      expect(
        find.text('Reiner Neymar will be assigned Goalkeeper (GK).'),
        findsOneWidget,
      );
    });

    testWidgets('re-picking the current position is a no-op', (tester) async {
      await pump(tester, position: PlayerPosition.leftWinger);
      await tester.tap(find.widgetWithText(TextButton, 'Change'));
      await tester.pumpAndSettle();
      await tapPosition(tester, 'Left Winger');

      // Nothing changed, so nothing to confirm.
      expect(find.text('Change position?'), findsNothing);
      expect(find.text('Left Winger (LW)'), findsOneWidget);
    });

    testWidgets('dismissing the sheet changes nothing', (tester) async {
      await pump(tester, position: PlayerPosition.leftWinger);
      await tester.tap(find.widgetWithText(TextButton, 'Change'));
      await tester.pumpAndSettle();
      // Tap the scrim above the sheet.
      await tester.tapAt(const Offset(300, 20));
      await tester.pumpAndSettle();

      expect(find.text('Change position?'), findsNothing);
      expect(find.text('Left Winger (LW)'), findsOneWidget);
    });
  });
}
