import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/registration_dependencies.dart';
import 'package:footpath_cebu/data/repositories/mock_club_member_repository.dart';
import 'package:footpath_cebu/domain/entities/player_registration.dart';
import 'package:footpath_cebu/domain/repositories/player_registration_repository.dart';
import 'package:footpath_cebu/presentation/providers/player_registration_providers.dart';
import 'package:footpath_cebu/presentation/screens/coordinator_create_account_screen.dart';

class _RegistrationRepository implements PlayerRegistrationRepository {
  int checkCalls = 0;
  int registerCalls = 0;
  PlayerRegistrationDraft? submitted;
  Object? checkError;
  Object? registrationError;
  Completer<PlayerRegistrationResult>? pending;

  @override
  Future<void> checkGuardian(GuardianRegistrationData guardian) async {
    checkCalls++;
    if (checkError case final error?) throw error;
  }

  @override
  Future<PlayerRegistrationResult> register(
    PlayerRegistrationDraft draft,
  ) async {
    registerCalls++;
    submitted = draft;
    if (registrationError case final error?) throw error;
    final completer = pending;
    if (completer != null) return completer.future;
    return PlayerRegistrationResult(
      playerId: 'player-2',
      guardianId: draft.existingGuardian?.id ?? 'guardian-2',
      coordinatorId: 'coordinator-1',
      guardianCreated: draft.existingGuardian == null,
      guardianEmail: draft.guardianEmail,
      guardianTemporaryPassword: draft.existingGuardian == null
          ? 'GuardianPass1'
          : null,
    );
  }
}

const _player = PlayerRegistrationData(
  firstName: 'Juan',
  lastName: 'Cruz',
  dateOfBirth: null,
);

PlayerRegistrationData validPlayer() => PlayerRegistrationData(
  firstName: _player.firstName,
  lastName: _player.lastName,
  dateOfBirth: DateTime(2012, 3, 2),
);

void main() {
  late _RegistrationRepository repository;
  late ProviderContainer container;

  Future<void> pumpFlow(WidgetTester tester) async {
    repository = _RegistrationRepository();
    container = ProviderContainer(
      overrides: [
        playerRegistrationRepositoryProvider.overrideWithValue(repository),
        mockClubMemberRepositoryProvider.overrideWithValue(
          MockClubMemberRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CoordinatorCreateAccountScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  PlayerRegistrationController controller() =>
      container.read(playerRegistrationControllerProvider.notifier);

  testWidgets('existing guardian creates and links a player', (tester) async {
    await pumpFlow(tester);
    expect(
      find.text('Does this player already have a guardian account?'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Yes'));
    await tester.pumpAndSettle();
    expect(find.text('Maria Santos'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Search guardians'),
      '0917',
    );
    await tester.pump();
    expect(find.text('Maria Santos'), findsOneWidget);
    await tester.tap(find.text('Maria Santos'));
    await tester.pumpAndSettle();

    controller().editPlayer(validPlayer());
    controller().review();
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Create player profile'),
    );
    await tester.pumpAndSettle();

    expect(repository.registerCalls, 1);
    expect(repository.submitted!.existingGuardian!.id, 'guardian-1');
    expect(find.text('Player profile added successfully.'), findsOneWidget);
    expect(find.text('Linked to Maria Santos.'), findsOneWidget);
  });

  testWidgets('new guardian stays temporary until player submission', (
    tester,
  ) async {
    await pumpFlow(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'No'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), ' Ana ');
    await tester.enterText(fields.at(1), 'D');
    await tester.enterText(fields.at(2), ' Cruz ');
    await tester.enterText(fields.at(3), 'ANA@EXAMPLE.COM');
    await tester.enterText(fields.at(4), '0918 123 4567');
    expect(repository.checkCalls, 0);
    expect(repository.registerCalls, 0);
    await tester.tap(find.text('Continue to player'));
    await tester.pumpAndSettle();

    expect(repository.checkCalls, 1);
    expect(find.text('Player information'), findsOneWidget);
    controller().editPlayer(validPlayer());
    controller().review();
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Create player profile'),
    );
    await tester.pumpAndSettle();

    expect(repository.registerCalls, 1);
    expect(repository.submitted!.existingGuardian, isNull);
    expect(repository.submitted!.guardian.email, 'ana@example.com');
    expect(
      find.text('Guardian account and player profile created successfully.'),
      findsOneWidget,
    );
  });

  testWidgets('invalid guardian fields remain on the form', (tester) async {
    await pumpFlow(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'No'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue to player'));
    await tester.pump();

    expect(find.text('This field is required.'), findsNWidgets(2));
    expect(
      find.text('Enter one letter for the middle initial.'),
      findsOneWidget,
    );
    expect(find.text('Email is required.'), findsOneWidget);
    expect(
      find.text('Enter a Philippine mobile number, e.g. 09171234567.'),
      findsOneWidget,
    );
    expect(repository.checkCalls, 0);
  });

  testWidgets('duplicate guardian offers the existing-guardian path', (
    tester,
  ) async {
    await pumpFlow(tester);
    repository.checkError = const PlayerRegistrationException(
      'A guardian with this email or mobile number already exists.',
      existingGuardianId: 'guardian-1',
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'No'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Maria');
    await tester.enterText(fields.at(1), 'D');
    await tester.enterText(fields.at(2), 'Santos');
    await tester.enterText(fields.at(3), 'maria.santos@example.com');
    await tester.enterText(fields.at(4), '09171234567');
    await tester.tap(find.text('Continue to player'));
    await tester.pumpAndSettle();

    expect(find.text('Use existing guardian'), findsOneWidget);
    await tester.tap(find.text('Use existing guardian'));
    await tester.pumpAndSettle();
    expect(find.text('Select guardian'), findsOneWidget);
    expect(find.text('Maria Santos'), findsOneWidget);
  });

  testWidgets('double submit sends one request and uncertain failure retries', (
    tester,
  ) async {
    await pumpFlow(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Yes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maria Santos'));
    controller().editPlayer(validPlayer());
    controller().review();
    repository.pending = Completer<PlayerRegistrationResult>();
    await tester.pump();
    final submit = find.widgetWithText(FilledButton, 'Create player profile');
    await tester.tap(submit);
    await tester.tap(submit);
    await tester.pump();
    expect(repository.registerCalls, 1);

    repository.pending!.completeError(
      const PlayerRegistrationException(
        'Could not confirm registration. Retry to check its status.',
        uncertain: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry registration'), findsOneWidget);
    expect(
      tester.widget<BackButton>(find.byType(BackButton)).onPressed,
      isNull,
    );
  });

  testWidgets(
    'back navigation preserves the guardian draft and cancel writes nothing',
    (tester) async {
      await pumpFlow(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'No'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Ana');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(
        find.text('Does this player already have a guardian account?'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'No'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(0))
            .initialValue,
        'Ana',
      );
      expect(repository.checkCalls, 0);
      expect(repository.registerCalls, 0);
    },
  );

  testWidgets('player form contains no email field', (tester) async {
    await pumpFlow(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Yes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maria Santos'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Player email'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Email'), findsNothing);
  });
}
