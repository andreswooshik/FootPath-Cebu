import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/registration_dependencies.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/club_member.dart';
import 'package:footpath_cebu/domain/entities/coordinator_person.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/domain/repositories/coordinator_people_repository.dart';
import 'package:footpath_cebu/presentation/providers/club_member_providers.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';
import 'package:footpath_cebu/presentation/screens/coordinator_people_screen.dart';
import 'package:footpath_cebu/presentation/screens/coordinator_person_details_screen.dart';

const _profile = UserProfile(
  id: 'coordinator-1',
  email: 'coordinator@example.com',
  firstName: 'Club',
  lastName: 'Coordinator',
  role: 'COORDINATOR',
  roleDisplay: 'Club Coordinator',
);

const _player = Player(
  id: 'player-1',
  name: 'John Santos',
  age: 14,
  classYear: 'Class of 2030',
  ageTier: AgeTier.development,
  eligibility: EligibilityStatus.pending,
  ratings: PlayerRatings(
    pace: 0,
    shooting: 0,
    passing: 0,
    dribbling: 0,
    defending: 0,
    physical: 0,
  ),
);

const _guardian = ClubMember(
  id: 'guardian-1',
  name: 'Maria Santos',
  role: ClubMemberRole.guardian,
  roleDisplay: 'Guardian',
  email: 'maria@example.com',
  linkedPlayers: ['John Santos'],
  linkedPlayerIds: ['player-1'],
);

const _coaches = [
  ClubMember(
    id: 'coach-1',
    name: 'Coach One',
    role: ClubMemberRole.coach,
    roleDisplay: 'Coach',
    email: 'one@example.com',
  ),
  ClubMember(
    id: 'coach-2',
    name: 'Coach Two',
    role: ClubMemberRole.coach,
    roleDisplay: 'Coach',
    email: 'two@example.com',
  ),
];

class _PeopleRepository implements CoordinatorPeopleRepository {
  int deleteCalls = 0;
  Object? deleteError;

  @override
  Future<CoordinatorPersonDetails> fetchDetails(
    CoordinatorPersonRole role,
    String id,
  ) async => const CoordinatorPersonDetails(
    id: 'guardian-1',
    role: CoordinatorPersonRole.guardian,
    firstName: 'Maria',
    middleInitial: 'D',
    lastName: 'Santos',
    name: 'Maria D. Santos',
    email: 'maria@example.com',
    mobileNumber: '+639171234567',
    linkedPeople: [
      CoordinatorPersonReference(id: 'player-1', name: 'John Santos'),
    ],
  );

  @override
  Future<void> deletePerson(CoordinatorPersonRole role, String id) async {
    deleteCalls++;
    if (deleteError case final error?) throw error;
  }
}

void main() {
  Future<void> pumpPeople(
    WidgetTester tester, {
    CoordinatorPeopleRepository? repository,
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          squadProvider.overrideWith((ref) async => const [_player]),
          clubMembersProvider.overrideWith((ref, role) async {
            return role == ClubMemberRole.guardian
                ? const [_guardian]
                : _coaches;
          }),
          if (repository != null)
            coordinatorPeopleRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: CoordinatorPeopleScreen(profile: _profile),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('loaded lists drive accurate singular and plural counts', (
    tester,
  ) async {
    await pumpPeople(tester);
    expect(find.text('1 player'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Guardians'));
    await tester.pumpAndSettle();
    expect(find.text('1 guardian'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Coaches'));
    await tester.pumpAndSettle();
    expect(find.text('Coach One'), findsOneWidget);
    expect(find.text('2 coaches'), findsOneWidget);
  });

  testWidgets('member row opens the ID-backed full details page', (
    tester,
  ) async {
    final repository = _PeopleRepository();
    await pumpPeople(tester, repository: repository);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Guardians'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maria Santos'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Guardian Details'), findsOneWidget);
    expect(find.text('Maria D. Santos'), findsOneWidget);
    expect(find.text('Linked players'), findsOneWidget);
    expect(find.text('John Santos'), findsOneWidget);
  });

  testWidgets('cancel does not delete and a blocked delete stays on details', (
    tester,
  ) async {
    final repository = _PeopleRepository()
      ..deleteError = const CoordinatorPeopleRepositoryException(
        'This guardian still has 1 linked player. Reassign or remove them before deleting this account.',
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coordinatorPeopleRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: CoordinatorPersonDetailsScreen(
            role: CoordinatorPersonRole.guardian,
            personId: 'guardian-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final deleteButton = find.widgetWithText(OutlinedButton, 'Delete Account');
    await tester.scrollUntilVisible(
      deleteButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(repository.deleteCalls, 0);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(repository.deleteCalls, 1);
    expect(find.textContaining('still has 1 linked player'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Guardian Details'), findsOneWidget);
  });
}
