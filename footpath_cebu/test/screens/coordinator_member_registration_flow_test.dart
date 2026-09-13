import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/registration_dependencies.dart';
import 'package:footpath_cebu/domain/entities/member_registration.dart';
import 'package:footpath_cebu/domain/repositories/member_registration_repository.dart';
import 'package:footpath_cebu/presentation/screens/coordinator_create_account_screen.dart';

class _MemberRepository implements MemberRegistrationRepository {
  int calls = 0;
  MemberAccountRole? role;
  MemberRegistrationData? data;

  @override
  Future<MemberRegistrationResult> create(
    MemberAccountRole role,
    MemberRegistrationData data,
  ) async {
    calls++;
    this.role = role;
    this.data = data;
    return MemberRegistrationResult(
      memberId: 'member-1',
      coordinatorId: 'coordinator-1',
      role: role,
      name: data.name,
      email: data.email,
      mobileNumber: data.mobileNumber,
      temporaryPassword: 'TempPass123',
    );
  }
}

void main() {
  late _MemberRepository repository;

  Future<void> pumpScreen(WidgetTester tester) async {
    repository = _MemberRepository();
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          memberRegistrationRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: CoordinatorCreateAccountScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fillValidForm(WidgetTester tester) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Maria');
    await tester.enterText(fields.at(1), 'd.');
    await tester.enterText(fields.at(2), 'Santos');
    await tester.enterText(fields.at(3), 'MARIA@EXAMPLE.COM');
    await tester.enterText(fields.at(4), '09171234567');
  }

  testWidgets('creates Guardian with required structured name and email', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Guardian'));
    await tester.pumpAndSettle();
    await fillValidForm(tester);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Create guardian account'),
    );
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    expect(repository.role, MemberAccountRole.guardian);
    expect(repository.data!.middleInitial, 'D');
    expect(repository.data!.email, 'maria@example.com');
    expect(find.text('Guardian account created successfully.'), findsOneWidget);
  });

  testWidgets('creates Coach and prevents a missing email submission', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Coach'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create coach account'));
    await tester.pump();
    expect(find.text('Email is required.'), findsOneWidget);
    expect(repository.calls, 0);

    await fillValidForm(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Create coach account'));
    await tester.pumpAndSettle();
    expect(repository.calls, 1);
    expect(repository.role, MemberAccountRole.coach);
    expect(find.text('Coach account created successfully.'), findsOneWidget);
  });

  testWidgets('creates Guardian without a middle initial', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Guardian'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Maria');
    await tester.enterText(fields.at(2), 'Santos');
    await tester.enterText(fields.at(3), 'maria@example.com');
    await tester.enterText(fields.at(4), '09171234567');
    await tester.tap(
      find.widgetWithText(FilledButton, 'Create guardian account'),
    );
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    expect(repository.data!.middleInitial, '');
    expect(find.text('Guardian account created successfully.'), findsOneWidget);
  });
}
