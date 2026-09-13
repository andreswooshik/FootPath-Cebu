import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/registration_dependencies.dart';
import 'package:footpath_cebu/data/repositories/mock_club_member_repository.dart';
import 'package:footpath_cebu/domain/entities/member_registration.dart';
import 'package:footpath_cebu/domain/entities/player_registration.dart';
import 'package:footpath_cebu/domain/repositories/member_registration_repository.dart';
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

class _MemberRepository implements MemberRegistrationRepository {
  int calls = 0;
  Object? error;

  @override
  Future<MemberRegistrationResult> create(
    MemberAccountRole role,
    MemberRegistrationData data,
  ) async {
    calls++;
    if (error case final failure?) throw failure;
    return MemberRegistrationResult(
      memberId: 'guardian-created',
      coordinatorId: 'coordinator-1',
      role: role,
      name: data.name,
      email: data.email,
      mobileNumber: data.mobileNumber,
      temporaryPassword: 'GuardianPass1',
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
  late _MemberRepository memberRepository;
  late ProviderContainer container;

  Future<void> pumpFlow(WidgetTester tester) async {
    repository = _RegistrationRepository();
    memberRepository = _MemberRepository();
    container = ProviderContainer(
      overrides: [
        playerRegistrationRepositoryProvider.overrideWithValue(repository),
        memberRegistrationRepositoryProvider.overrideWithValue(
          memberRepository,
        ),
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

  testWidgets('No reuses Guardian account flow and passes its ID to Player', (
    tester,
  ) async {
    await pumpFlow(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'No'));
    await tester.pumpAndSettle();

    expect(find.text('Create guardian account'), findsWidgets);
    expect(find.text('Guardian information'), findsNothing);
    expect(
      tester
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>))
          .onSelectionChanged,
      isNull,
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), ' Ana ');
    await tester.enterText(fields.at(1), 'D');
    await tester.enterText(fields.at(2), ' Cruz ');
    await tester.enterText(fields.at(3), 'ANA@EXAMPLE.COM');
    await tester.enterText(fields.at(4), '0918 123 4567');
    await tester.tap(
      find.widgetWithText(FilledButton, 'Create guardian account'),
    );
    await tester.pumpAndSettle();

    expect(memberRepository.calls, 1);
    expect(repository.checkCalls, 0);
    expect(find.text('Player information'), findsOneWidget);
    controller().editPlayer(validPlayer());
    controller().review();
    await tester.pump();
    expect(find.text('New guardian'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Create player profile'),
    );
    await tester.pumpAndSettle();

    expect(repository.registerCalls, 1);
    expect(repository.submitted!.existingGuardian!.id, 'guardian-created');
    expect(repository.submitted!.existingGuardian!.email, 'ana@example.com');
    expect(
      find.text('Guardian account and player profile created successfully.'),
      findsOneWidget,
    );
    expect(find.textContaining('GuardianPass1'), findsOneWidget);
  });

  testWidgets('invalid guardian fields remain on the form', (tester) async {
    await pumpFlow(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'No'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Create guardian account'),
    );
    await tester.pump();

    expect(find.text('This field is required.'), findsNWidgets(2));
    expect(find.text('Middle initial (optional)'), findsOneWidget);
    expect(find.text('Enter one letter for the middle initial.'), findsNothing);
    expect(find.text('Email is required.'), findsOneWidget);
    expect(
      find.text('Enter a Philippine mobile number, e.g. 09171234567.'),
      findsOneWidget,
    );
    expect(memberRepository.calls, 0);
    expect(repository.registerCalls, 0);
  });

  testWidgets('Guardian failure stays on the reused account screen', (
    tester,
  ) async {
    await pumpFlow(tester);
    memberRepository.error = const MemberRegistrationException(
      'An account with this email already exists.',
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'No'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Maria');
    await tester.enterText(fields.at(1), 'D');
    await tester.enterText(fields.at(2), 'Santos');
    await tester.enterText(fields.at(3), 'maria.santos@example.com');
    await tester.enterText(fields.at(4), '09171234567');
    await tester.tap(
      find.widgetWithText(FilledButton, 'Create guardian account'),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('An account with this email already exists.'),
      findsOneWidget,
    );
    expect(find.text('Create guardian account'), findsWidgets);
    expect(find.text('Player information'), findsNothing);
    expect(repository.registerCalls, 0);
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

  testWidgets('back from Guardian account returns to the guardian question', (
    tester,
  ) async {
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
    expect(memberRepository.calls, 0);
    expect(repository.registerCalls, 0);
  });

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
