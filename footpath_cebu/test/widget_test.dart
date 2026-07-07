// Smoke test for the login screen. Pumps LoginScreen directly (no Firebase
// initialization is needed until the sign-in button is pressed).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:footpath_cebu/screens/login_screen.dart';

void main() {
  testWidgets('Login screen renders email/password fields and button',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('FootPath Cebu'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign In'), findsOneWidget);
  });
}
