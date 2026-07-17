import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/presentation/screens/dispute_list_screen.dart';
import 'package:footpath_cebu/presentation/screens/flag_dispute_screen.dart';

const _player = Player(
  id: 'p1',
  name: 'Rhobert Ronaldo',
  age: 17,
  classYear: 'Class of 2027',
  ageTier: AgeTier.pathway,
  ratings: PlayerRatings(
    pace: 80, shooting: 80, passing: 80,
    dribbling: 80, defending: 80, physical: 80,
  ),
  eligibility: EligibilityStatus.eligible,
);

void main() {
  /// Repository providers default to the in-memory mocks in a test
  /// environment; MockDisputeRepository seeds one under-review dispute.
  /// Tall surface so bottom-sheet content stays hit-testable.
  Future<void> pumpList(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(520, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: DisputeListScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('DisputeListScreen', () {
    testWidgets('lists disputes with category, player, and status',
        (tester) async {
      await pumpList(tester);

      expect(find.text('Attendance mark disputed'), findsOneWidget);
      expect(
        find.textContaining('Attendance · Rhobert Ronaldo'),
        findsOneWidget,
      );
      expect(find.text('Under Review'), findsOneWidget);
    });

    testWidgets('tapping a dispute opens its thread and posts a response',
        (tester) async {
      await pumpList(tester);

      await tester.tap(find.text('Attendance mark disputed'));
      await tester.pumpAndSettle();

      // The thread shows the seeded staff response.
      expect(find.text('Thread'), findsOneWidget);
      expect(
        find.text('Checking the sign-in sheet with the P.E. department.'),
        findsOneWidget,
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Your response'),
        'Adding the drill list from that day.',
      );
      await tester.tap(find.text('Post Response'));
      await tester.pumpAndSettle();

      expect(find.text('Response posted.'), findsOneWidget);
    });

    testWidgets('an empty response is blocked', (tester) async {
      await pumpList(tester);

      await tester.tap(find.text('Attendance mark disputed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Post Response'));
      await tester.pumpAndSettle();

      expect(find.text('Write a response first.'), findsOneWidget);
    });
  });

  group('FlagDisputeScreen', () {
    Future<void> pumpFlag(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(520, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: FlagDisputeScreen(player: _player)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the subject player and requires a summary',
        (tester) async {
      await pumpFlag(tester);

      expect(find.text('Rhobert Ronaldo'), findsOneWidget);
      expect(find.text('Subject of this dispute'), findsOneWidget);

      await tester.tap(find.text('Raise Dispute'));
      await tester.pumpAndSettle();
      expect(find.text('A summary is required.'), findsOneWidget);
    });

    testWidgets('a valid dispute saves and pops back to the caller',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(520, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Pushed like the real app (from the player profile) so the success
      // pop has a route to return to.
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const FlagDisputeScreen(player: _player),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Summary *'),
        'Attendance mark disputed again',
      );
      await tester.tap(find.text('Raise Dispute'));
      await tester.pumpAndSettle();

      expect(find.text('Dispute raised.'), findsOneWidget);
      // The screen popped back to its caller.
      expect(find.text('open'), findsOneWidget);
      expect(find.text('Flag Dispute'), findsNothing);
    });
  });
}
