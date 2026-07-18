import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/screens/coach_dashboard_screen.dart';
import 'package:footpath_cebu/presentation/widgets/mini_player_card.dart';

const _coach = UserProfile(
  id: 'c1',
  email: 'coach@example.com',
  firstName: 'Ralf',
  lastName: 'Cruz',
  role: 'COACH',
  roleDisplay: 'Coach',
);

/// Each test gets its own ProviderScope, so provider state (squad, filters)
/// never leaks between tests. The repository providers default to the
/// in-memory mocks in a test environment (see core/di/providers.dart).
Widget _app() => const ProviderScope(
      child: MaterialApp(home: CoachDashboardScreen(profile: _coach)),
    );

/// The dashboard scrolls the Team Overview above the roster, so give the test
/// a phone-tall viewport — otherwise the lazily-built roster slivers fall
/// below the default 800x600 window and never render.
void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('shows a loading spinner, then the mock roster', (tester) async {
    _tallView(tester);
    await tester.pumpWidget(_app());

    // First frame: squad is still loading.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Let the mock repository's simulated latency resolve.
    await tester.pumpAndSettle();

    expect(find.text('Active Squad Roster'), findsOneWidget);
    // The roster defaults to the compact mini-card list.
    expect(find.byType(MiniPlayerCard), findsWidgets);
    expect(find.text('Rhobert Ronaldo'), findsOneWidget);
  });

  testWidgets('search filters the roster', (tester) async {
    _tallView(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'messi');
    await tester.pumpAndSettle();

    expect(find.text('Ralf Andre Messi'), findsOneWidget);
    expect(find.text('Rhobert Ronaldo'), findsNothing);
  });

  testWidgets('renders a tier filter chip per tier, plus All', (tester) async {
    _tallView(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // Counts come from the mock squad: 2 Foundation, 4 Development, 4 Pathway.
    expect(find.widgetWithText(FilterChip, 'All (10)'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Foundation (2)'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Development (4)'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Pathway (4)'), findsOneWidget);
  });

  testWidgets('tapping a tier chip shows only that tier', (tester) async {
    _tallView(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // The Team Overview sits above the filter row, so scroll the chip into
    // view before tapping it.
    await tester.ensureVisible(find.widgetWithText(FilterChip, 'Foundation (2)'));
    await tester.tap(find.widgetWithText(FilterChip, 'Foundation (2)'));
    await tester.pumpAndSettle();

    // Foundation players only.
    expect(find.text('Lamine Yamashita'), findsOneWidget);
    expect(find.text('Pedri Villanueva'), findsOneWidget);
    // A Pathway player is now hidden.
    expect(find.text('Rhobert Ronaldo'), findsNothing);

    // Re-tapping the active chip clears the filter.
    await tester.ensureVisible(find.widgetWithText(FilterChip, 'Foundation (2)'));
    await tester.tap(find.widgetWithText(FilterChip, 'Foundation (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Rhobert Ronaldo'), findsOneWidget);
  });

  testWidgets('an empty tier explains itself', (tester) async {
    _tallView(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(FilterChip, 'Foundation (2)'));
    await tester.tap(find.widgetWithText(FilterChip, 'Foundation (2)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();

    expect(find.text('No Foundation players match your search.'), findsOneWidget);
  });

  testWidgets('renders the bottom navigation destinations', (tester) async {
    _tallView(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Squad'), findsOneWidget);
    expect(find.text('Training'), findsOneWidget);
    expect(find.text('Progress'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });
}
