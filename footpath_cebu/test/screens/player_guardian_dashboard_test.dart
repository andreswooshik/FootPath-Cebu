import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/presentation/screens/guardian_dashboard_screen.dart';
import 'package:footpath_cebu/presentation/screens/portal_shell_screen.dart';
import 'package:footpath_cebu/presentation/widgets/player_card.dart';

void main() {
  testWidgets('Player must create a privacy PIN before seeing the dashboard', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: PlayerPortalScreen())),
    );

    expect(find.byType(MotionSkeleton), findsWidgets);
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
    await tester.pumpAndSettle();
    expect(find.text('Recent Attendance'), findsOneWidget);
    expect(find.text('View Full History'), findsOneWidget);
  });

  testWidgets('Guardian dashboard shows the linked child selector', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: GuardianDashboardScreen())),
    );

    expect(find.byType(MotionSkeleton), findsWidgets);
    await tester.pumpAndSettle();
    // The dashboard loads in two phases: linked children first, then that
    // child's attendance (a second delayed timer, started once the child's
    // sections build). Drain the attendance timer so none is left pending at
    // teardown.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('My Players'), findsOneWidget);
    // No child-scoped information is shown until the guardian chooses a
    // player explicitly.
    expect(find.byType(PlayerCard), findsNothing);
    expect(find.byType(DropdownButton<String>), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ralf Andre Messi').last);
    await tester.pumpAndSettle();
    expect(find.byType(PlayerCard), findsOneWidget);

    // The attendance section sits below the fold — scroll it into view.
    await tester.scrollUntilVisible(
      find.text('Recent Attendance'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Recent Attendance'), findsOneWidget);
    expect(find.text('View Full History'), findsOneWidget);
  });

  testWidgets('Guardian notification route selects a safe default schedule', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: GuardianPortalScreen(
            initialTabIndex: 1,
            selectDefaultPlayer: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(find.text('Schedule'), findsOneWidget);
  });
}
