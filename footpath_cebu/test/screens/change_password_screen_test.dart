import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/domain/repositories/auth_repository.dart';
import 'package:footpath_cebu/presentation/screens/change_password_screen.dart';

class _FakeAuthRepo implements AuthRepository {
  String? lastCurrent;
  String? lastNew;
  String? lastResetEmail;
  Object? throwOnChange;

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    lastCurrent = currentPassword;
    lastNew = newPassword;
    final e = throwOnChange;
    if (e != null) throw e;
  }

  @override
  Future<UserProfile> signInAndFetchProfile({
    required String email,
    required String password,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    lastResetEmail = email;
  }
}

/// Pushes the screen from a host route so popping on success is observable.
Future<void> _pumpAndOpen(
  WidgetTester tester,
  AuthRepository repo, {
  String? email,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChangePasswordScreen(email: email),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _fillAndSubmit(
  WidgetTester tester, {
  required String current,
  required String next,
  required String confirm,
}) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), current);
  await tester.enterText(fields.at(1), next);
  await tester.enterText(fields.at(2), confirm);
  await tester.tap(find.widgetWithText(FilledButton, 'Change Password'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a successful change confirms and returns to the profile',
      (tester) async {
    final repo = _FakeAuthRepo();
    await _pumpAndOpen(tester, repo);

    await _fillAndSubmit(
      tester,
      current: 'old-secret-1',
      next: 'new-secret-1',
      confirm: 'new-secret-1',
    );

    expect(repo.lastCurrent, 'old-secret-1');
    expect(repo.lastNew, 'new-secret-1');
    expect(find.byType(ChangePasswordScreen), findsNothing);
    expect(find.text('Password changed successfully.'), findsOneWidget);
  });

  testWidgets('a validation error keeps the screen open and shows the rule',
      (tester) async {
    final repo = _FakeAuthRepo();
    await _pumpAndOpen(tester, repo);

    await _fillAndSubmit(
      tester,
      current: 'old-secret-1',
      next: 'new-secret-1',
      confirm: 'different-1',
    );

    expect(repo.lastCurrent, isNull, reason: 'repo must not be called');
    expect(find.byType(ChangePasswordScreen), findsOneWidget);
    expect(find.text('New passwords do not match.'), findsOneWidget);
  });

  testWidgets('a wrong current password shows the auth error',
      (tester) async {
    final repo = _FakeAuthRepo()
      ..throwOnChange = AuthException('Current password is incorrect.');
    await _pumpAndOpen(tester, repo);

    await _fillAndSubmit(
      tester,
      current: 'wrong-secret',
      next: 'new-secret-1',
      confirm: 'new-secret-1',
    );

    expect(find.byType(ChangePasswordScreen), findsOneWidget);
    expect(find.text('Current password is incorrect.'), findsOneWidget);
  });

  testWidgets('all fields obscure input until the visibility toggle is used',
      (tester) async {
    await _pumpAndOpen(tester, _FakeAuthRepo());

    List<bool> obscured() => tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.obscureText)
        .toList();

    expect(obscured(), [true, true, true]);

    await tester.tap(find.byIcon(Icons.visibility_off).first);
    await tester.pump();

    expect(obscured(), [false, false, false]);
  });

  testWidgets('the reset-email fallback appears only when the email is known',
      (tester) async {
    await _pumpAndOpen(tester, _FakeAuthRepo());
    expect(find.text('Forgot your current password?'), findsNothing);
  });

  testWidgets('the reset-email fallback sends to the given address',
      (tester) async {
    final repo = _FakeAuthRepo();
    await _pumpAndOpen(tester, repo, email: 'coach@example.com');

    await tester.tap(find.text('Forgot your current password?'));
    await tester.pumpAndSettle();

    expect(repo.lastResetEmail, 'coach@example.com');
    expect(
      find.text('Password reset email sent to coach@example.com.'),
      findsOneWidget,
    );
  });
}
