import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/presentation/screens/guardian_dashboard_screen.dart';
import 'package:footpath_cebu/presentation/screens/player_dashboard_screen.dart';
import 'package:footpath_cebu/presentation/widgets/player_card.dart';

void main() {
  testWidgets('Player must create a privacy PIN before seeing the dashboard', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: PlayerDashboardScreen())),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Create your privacy PIN'), findsOneWidget);
    expect(find.byType(PlayerCard), findsNothing);
    final pinFields = find.byType(TextField);
    await tester.enterText(pinFields.at(0), '1234');
    await tester.enterText(pinFields.at(1), '1234');
    await tester.tap(find.text('Create PIN and continue'));
    await tester.pumpAndSettle();

    // Attendance loads on a second delayed timer, started once the dashboard
    // sections build. Drain it so none is left pending at teardown.
    await tester.pump(const Duration(milliseconds: 300));
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

  testWidgets('Guardian dashboard shows the linked child selector', (
    tester,
  ) async {
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
    // The guardian can switch between all linked players.
    expect(find.byType(PlayerCard), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsOneWidget);

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
