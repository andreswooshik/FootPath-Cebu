import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/club_registration_dependencies.dart';
import 'package:footpath_cebu/domain/entities/club_registration.dart';
import 'package:footpath_cebu/domain/repositories/club_registration_repository.dart';
import 'package:footpath_cebu/presentation/providers/club_registration_controller.dart';
import 'package:footpath_cebu/presentation/screens/club_registration_screen.dart';
import 'package:footpath_cebu/presentation/screens/login_screen.dart';

class _RegistrationRepository implements ClubRegistrationRepository {
  int calls = 0;
  ClubRegistrationApplication? application;

  @override
  Future<ClubRegistrationResult> submit(
    ClubRegistrationApplication application,
  ) async {
    calls++;
    this.application = application;
    return ClubRegistrationResult(
      status: 'PENDING',
      coordinatorEmail: application.email,
    );
  }
}

CoachLicenseSelection _license({String name = 'coach-license.pdf'}) =>
    CoachLicenseSelection(
      filename: name,
      extension: 'pdf',
      bytes: Uint8List.fromList(<int>[37, 80, 68, 70, 45, 49, 46, 52]),
    );

void main() {
  Future<void> setPhoneSize(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('login exposes club registration as a secondary action', (
    tester,
  ) async {
    await setPhoneSize(tester);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Register your club'), findsOneWidget);
    expect(find.text('For new club coordinators only.'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('register-club-link')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('register-club-link')));
    await tester.pumpAndSettle();

    expect(find.byType(ClubRegistrationScreen), findsOneWidget);
    expect(find.text('Apply to join FootPath'), findsOneWidget);
  });

  testWidgets('empty registration shows validation and preserves the page', (
    tester,
  ) async {
    await setPhoneSize(tester);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ClubRegistrationScreen())),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('submit-club-application')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('submit-club-application')));
    await tester.pump();

    expect(find.text('This field is required.'), findsWidgets);
    expect(find.byType(ClubRegistrationScreen), findsOneWidget);
  });

  testWidgets('valid application is submitted as pending and opens success', (
    tester,
  ) async {
    await setPhoneSize(tester);
    final repository = _RegistrationRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clubRegistrationRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: ClubRegistrationScreen(
            pickCoachLicense: () async => _license(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '  Cebu Mobile FC  ');
    await tester.enterText(fields.at(1), 'Jamie Cruz');
    await tester.enterText(fields.at(2), 'Coach Santos');
    await tester.enterText(fields.at(3), 'CVFA-100');
    await tester.enterText(fields.at(4), 'JAMIE@MOBILE.TEST');
    await tester.enterText(fields.at(5), 'Str0ng!passphrase9');
    await tester.enterText(fields.at(6), 'Str0ng!passphrase9');
    await tester.ensureVisible(find.byKey(const Key('coach-license-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('coach-license-picker')));
    await tester.pumpAndSettle();

    expect(find.text('coach-license.pdf'), findsOneWidget);
    expect(find.text('JPG, PNG or PDF, max 50 MB.'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('submit-club-application')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('submit-club-application')));
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    expect(repository.application!.clubName, 'Cebu Mobile FC');
    expect(repository.application!.email, 'jamie@mobile.test');
    expect(find.byType(ClubRegistrationSuccessScreen), findsOneWidget);
    expect(find.text('Application submitted'), findsNWidgets(2));
  });

  test('license selection rejects unsupported extensions', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final error = container
        .read(clubRegistrationControllerProvider.notifier)
        .setLicense(
          bytes: Uint8List.fromList([1, 2, 3]),
          filename: 'license.docx',
          extension: 'docx',
        );

    expect(error, 'Only JPG, PNG, and PDF files are allowed.');
    expect(container.read(clubRegistrationControllerProvider).license, isNull);
  });
}
