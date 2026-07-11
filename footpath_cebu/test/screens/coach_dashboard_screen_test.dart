import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/service_locator.dart';
import 'package:footpath_cebu/presentation/screens/coach_dashboard_screen.dart';
import 'package:footpath_cebu/presentation/widgets/player_card.dart';

void main() {
  setUp(ServiceLocator.initMock);

  testWidgets('shows a loading spinner, then the mock roster', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CoachDashboardScreen()),
    );

    // First frame: squad is still loading.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Let the mock repository's simulated latency resolve.
    await tester.pumpAndSettle();

    expect(find.text('Active Squad Roster'), findsOneWidget);
    expect(find.byType(PlayerCard), findsWidgets);
    expect(find.text('Rhobert Ronaldo'), findsOneWidget);
  });

  testWidgets('search filters the roster', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CoachDashboardScreen()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'messi');
    await tester.pumpAndSettle();

    expect(find.text('Ralf Andre Messi'), findsOneWidget);
    expect(find.text('Rhobert Ronaldo'), findsNothing);
  });

  testWidgets('renders the bottom navigation destinations', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CoachDashboardScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Squad'), findsOneWidget);
    expect(find.text('Training'), findsOneWidget);
    expect(find.text('Progress'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });
}
