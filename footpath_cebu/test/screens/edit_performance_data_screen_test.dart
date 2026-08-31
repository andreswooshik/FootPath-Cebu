import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/data/repositories/mock_growth_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_player_repository.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/screens/edit_performance_data_screen.dart';

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
        pace: 91, shooting: 82, passing: 73, dribbling: 64, defending: 55,
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
        pace: 1, shooting: 1, passing: 1, dribbling: 1, defending: 1,
        physical: 1,
        diving: 88, handling: 85, kicking: 70, reflexes: 92, speed: 62,
        positioning: 86,
      ),
    );

Future<void> _pump(WidgetTester tester, Player player) async {
  await tester.binding.setSurfaceSize(const Size(600, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        growthRepositoryProvider.overrideWithValue(MockGrowthRepository()),
      ],
      child: MaterialApp(
        home: EditPerformanceDataScreen(player: player, profile: _coach),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('EditPerformanceDataScreen slider labels', () {
    testWidgets('an outfield player gets the outfield sliders', (
      tester,
    ) async {
      await _pump(tester, _outfield());

      for (final label in [
        'PAC (Pace)',
        'SHO (Shooting)',
        'PAS (Passing)',
        'DRI (Dribbling)',
        'DEF (Defending)',
        'PHY (Physicality)',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      for (final label in [
        'DIV (Diving)',
        'HAN (Handling)',
        'KIC (Kicking)',
        'REF (Reflexes)',
        'SPD (Speed)',
        'POS (Positioning)',
      ]) {
        expect(find.text(label), findsNothing);
      }
      // 6 sliders total either way — not 12.
      expect(find.byType(Slider), findsNWidgets(6));
    });

    testWidgets('a goalkeeper gets the GK sliders, not the outfield ones', (
      tester,
    ) async {
      await _pump(tester, _goalkeeper());

      for (final label in [
        'DIV (Diving)',
        'HAN (Handling)',
        'KIC (Kicking)',
        'REF (Reflexes)',
        'SPD (Speed)',
        'POS (Positioning)',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      for (final label in [
        'PAC (Pace)',
        'SHO (Shooting)',
        'PAS (Passing)',
        'DRI (Dribbling)',
        'DEF (Defending)',
        'PHY (Physicality)',
      ]) {
        expect(find.text(label), findsNothing);
      }
      expect(find.byType(Slider), findsNWidgets(6));
    });

    testWidgets('the Coach Evaluation notes box is unchanged for a goalkeeper',
      (tester) async {
        await _pump(tester, _goalkeeper());

        expect(find.text('Coach Evaluation'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows live previous deltas and allows a review reason', (
      tester,
    ) async {
      await _pump(tester, _outfield());

      expect(find.textContaining('Previous assessment'), findsOneWidget);
      expect(find.textContaining('Prev 76'), findsNWidgets(6));
      final pace = tester.widget<Slider>(find.byType(Slider).first);
      pace.onChanged!(80);
      await tester.pump();
      expect(find.text('Prev 76\n+4'), findsOneWidget);

      await tester.tap(find.text('General review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Monthly review').last);
      await tester.pumpAndSettle();
      expect(find.text('Monthly review'), findsOneWidget);
    });
  });

  group('EditPerformanceDataScreen save — GK/outfield isolation', () {
    testWidgets(
      'saving a GK assessment edits the GK six and preserves the '
      'unedited outfield six',
      (tester) async {
        // Self-contained: capture "before", drive the screen, verify "after"
        // — no dependency on MockPlayerRepository's static squad state from
        // any other test.
        //
        // fetchSquad() opens with a 500ms Future.delayed. A testWidgets body
        // runs in a fake-async zone where timers only fire when a pump
        // advances the clock — awaiting that future directly deadlocks the
        // test forever (a real-time timeout, not a pumpAndSettle one).
        // runAsync escapes to real timers for the fetch.
        final repo = MockPlayerRepository();
        final before = (await tester.runAsync(() => repo.fetchSquad()))!
            .firstWhere((p) => p.id == 'p7');
        final originalOutfield = before.ratings;

        await tester.binding.setSurfaceSize(const Size(600, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // Pushed onto a real stack rather than `_pump`'s `home:` — _save()
        // calls Navigator.pop() after a successful save, and popping the
        // sole route in a `home:`-only stack leaves the Navigator unable to
        // settle, hanging pumpAndSettle() indefinitely. This mirrors how the
        // screen is always reached for real, via Navigator.push from
        // PlayerProfileScreen.
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EditPerformanceDataScreen(
                            player: before,
                            profile: _coach,
                          ),
                        ),
                      ),
                      child: const Text('Open editor'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open editor'));
        await tester.pumpAndSettle();

        // Sliders render in declared order for a GK: DIV, HAN, KIC, REF,
        // SPD, POS — drive the first (DIV) directly via its onChanged, the
        // same pattern as simulating a drag without gesture-distance math.
        final divSlider = tester.widget<Slider>(find.byType(Slider).first);
        divSlider.onChanged!(77);
        await tester.pump();

        await tester.tap(find.widgetWithText(FilledButton, 'Save & Sync'));
        await tester.pumpAndSettle();

        expect(find.text('Assessment saved for Gianluigi Dela Cruz.'),
            findsOneWidget);

        final after = (await tester.runAsync(() => repo.fetchSquad()))!
            .firstWhere((p) => p.id == 'p7');
        // The edited value stuck...
        expect(after.ratings.diving, 77);
        // ...and every unedited GK value plus the whole outfield six are
        // untouched — the bug this design guards against would zero these.
        expect(after.ratings.handling, before.ratings.handling);
        expect(after.ratings.kicking, before.ratings.kicking);
        expect(after.ratings.reflexes, before.ratings.reflexes);
        expect(after.ratings.speed, before.ratings.speed);
        expect(after.ratings.positioning, before.ratings.positioning);
        expect(after.ratings.pace, originalOutfield.pace);
        expect(after.ratings.shooting, originalOutfield.shooting);
        expect(after.ratings.passing, originalOutfield.passing);
        expect(after.ratings.dribbling, originalOutfield.dribbling);
        expect(after.ratings.defending, originalOutfield.defending);
        expect(after.ratings.physical, originalOutfield.physical);
      },
    );
  });
}
