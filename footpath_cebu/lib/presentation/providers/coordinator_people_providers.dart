import 'package:footpath_cebu/presentation/providers/mutation_controller.dart';
import 'package:footpath_cebu/presentation/providers/club_member_providers.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';
import 'package:footpath_cebu/domain/entities/club_member.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/core/di/registration_dependencies.dart';
import 'package:footpath_cebu/domain/entities/coordinator_person.dart';

class CoordinatorPersonKey {
  const CoordinatorPersonKey(this.role, this.id);

  final CoordinatorPersonRole role;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is CoordinatorPersonKey && other.role == role && other.id == id;

  @override
  int get hashCode => Object.hash(role, id);
}

final coordinatorPersonDetailsProvider = FutureProvider.autoDispose
    .family<CoordinatorPersonDetails, CoordinatorPersonKey>(
      (ref, key) => ref
          .watch(coordinatorPeopleRepositoryProvider)
          .fetchDetails(key.role, key.id),
    );

class CoordinatorPersonController extends MutationController {
  Future<bool> delete(CoordinatorPersonKey key) async =>
      await runMutation(
        () async {
          await ref
              .read(coordinatorPeopleRepositoryProvider)
              .deletePerson(key.role, key.id);
          return true;
        },
        onSuccess: (_) {
          ref.invalidate(coordinatorPersonDetailsProvider(key));
          ref.invalidate(squadProvider);
          ref.invalidate(clubMembersProvider(ClubMemberRole.guardian));
          ref.invalidate(clubMembersProvider(ClubMemberRole.coach));
        },
      ) ??
      false;
}

final coordinatorPersonControllerProvider = AsyncNotifierProvider.autoDispose
    .family<CoordinatorPersonController, void, CoordinatorPersonKey>(
      (_) => CoordinatorPersonController(),
    );
