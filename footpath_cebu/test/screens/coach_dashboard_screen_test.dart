import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/service_locator.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/screens/coach_dashboard_screen.dart';
import 'package:footpath_cebu/presentation/widgets/player_card.dart';

const _coach = UserProfile(
  id: 'c1',
  email: 'coach@example.com',
  firstName: 'Ralf',
  lastName: 'Cruz',
  role: 'COACH',
  roleDisplay: 'Coach',
);

void main() {
  setUp(ServiceLocator.initMock);

  testWidgets('shows a loading spinner, then the mock roster', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CoachDashboardScreen(profile: _coach)),
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
      const MaterialApp(home: CoachDashboardScreen(profile: _coach)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'messi');
    await tester.pumpAndSettle();

    expect(find.text('Ralf Andre Messi'), findsOneWidget);
    expect(find.text('Rhobert Ronaldo'), findsNothing);
  });

  testWidgets('renders a tier filter chip per tier, plus All', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CoachDashboardScreen(profile: _coach)),
    );
    await tester.pumpAndSettle();

    // Counts come from the mock squad: 2 Foundation, 4 Development, 4 Pathway.
    expect(find.widgetWithText(FilterChip, 'All (10)'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Foundation (2)'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Development (4)'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Pathway (4)'), findsOneWidget);
  });

  testWidgets('tapping a tier chip shows only that tier', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CoachDashboardScreen(profile: _coach)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, 'Foundation (2)'));
    await tester.pumpAndSettle();

    // Foundation players only.
    expect(find.text('Lamine Yamashita'), findsOneWidget);
    expect(find.text('Pedri Villanueva'), findsOneWidget);
    // A Pathway player is now hidden.
    expect(find.text('Rhobert Ronaldo'), findsNothing);

    // Re-tapping the active chip clears the filter.
    await tester.tap(find.widgetWithText(FilterChip, 'Foundation (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Rhobert Ronaldo'), findsOneWidget);
  });

  testWidgets('an empty tier explains itself', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CoachDashboardScreen(profile: _coach)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, 'Foundation (2)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();

    expect(find.text('No Foundation players match your search.'), findsOneWidget);
  });

  testWidgets('renders the bottom navigation destinations', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CoachDashboardScreen(profile: _coach)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Squad'), findsOneWidget);
    expect(find.text('Training'), findsOneWidget);
    expect(find.text('Progress'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });
}
