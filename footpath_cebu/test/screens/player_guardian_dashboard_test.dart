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
    // The shared portal shell's four tabs.
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Progress'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    // The attendance section sits below the fold — scroll it into view.
    await tester.scrollUntilVisible(
      find.text('Recent Attendance'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Recent Attendance'), findsOneWidget);
    expect(find.text('View Full History'), findsOneWidget);
  });

  testWidgets('Guardian dashboard shows the linked child, no child selector',
      (tester) async {
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
    // The dashboard mirrors the Player portal now: the guardian's first
    // linked child shows directly, with no picker to switch children.
    expect(find.byType(PlayerCard), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsNothing);

    // The attendance section sits below the fold — scroll it into view.
    await tester.scrollUntilVisible(
      find.text('Recent Attendance'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Recent Attendance'), findsOneWidget);
    expect(find.text('View Full History'), findsOneWidget);
  });
}
