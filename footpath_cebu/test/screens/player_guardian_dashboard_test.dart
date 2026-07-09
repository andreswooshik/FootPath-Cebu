import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/repositories/service_locator.dart';
import 'package:footpath_cebu/screens/guardian_dashboard_screen.dart';
import 'package:footpath_cebu/screens/player_dashboard_screen.dart';
import 'package:footpath_cebu/widgets/player_card.dart';

void main() {
  setUp(ServiceLocator.initMock);

  testWidgets('Player dashboard shows the player card after loading',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PlayerDashboardScreen()),
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

  testWidgets('Guardian dashboard lists linked children', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: GuardianDashboardScreen()),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('My Players'), findsOneWidget);
    // Mock links two children (p2 + p3).
    expect(find.byType(PlayerCard), findsNWidgets(2));
    expect(find.text('2 linked players'), findsOneWidget);
  });
}
