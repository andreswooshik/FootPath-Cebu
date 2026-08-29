import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/screens/coordinator_account_screen.dart';
import 'package:footpath_cebu/presentation/widgets/responsive_content.dart';

void main() {
  testWidgets('responsive portal content remains readable on tablets', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ResponsiveContent(
            child: SizedBox(key: Key('content'), width: double.infinity),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(const Key('content'))).width, 760);
  });

  testWidgets('Coordinator profile follows the shared account hierarchy', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(820, 1180));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const profile = UserProfile(
      id: 'coordinator-1',
      email: 'coordinator@example.com',
      firstName: 'Club',
      lastName: 'Coordinator',
      role: 'COORDINATOR',
      roleDisplay: 'Coordinator',
    );
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: CoordinatorAccountScreen(profile: profile)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Profile'), findsOneWidget);
    expect(find.text('Change password'), findsOneWidget);
    expect(find.text('Mobile access'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
