import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/presentation/screens/guardian_dashboard_screen.dart';
import 'package:footpath_cebu/presentation/screens/player_dashboard_screen.dart';
import 'package:footpath_cebu/presentation/widgets/player_card.dart';

void main() {
  testWidgets('Player dashboard shows the player card after loading',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: PlayerDashboardScreen())),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('My Profile'), findsOneWidget);
    expect(find.byType(PlayerCard), findsOneWidget);

    // The feedback section sits below the fold — scroll it into view.
    await tester.scrollUntilVisible(
      find.text('Feedback & Ratings'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Feedback & Ratings'), findsOneWidget);
  });

  testWidgets('Guardian dashboard shows the selected child', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: GuardianDashboardScreen())),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    // The dashboard loads in two phases: linked children first, then that
    // child's attendance (a second delayed timer, started once the child's
    // sections build). Drain the attendance timer so none is left pending at
    // teardown.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('My Players'), findsOneWidget);
    // The redesigned dashboard shows one child at a time (with a selector to
    // switch between the two linked children, p2 + p3), not a list — so
    // exactly one player card is on screen.
    expect(find.byType(PlayerCard), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsOneWidget);

    // The attendance section sits below the fold — scroll it into view.
    await tester.scrollUntilVisible(
      find.text('Recent Attendance'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Recent Attendance'), findsOneWidget);
  });
}
