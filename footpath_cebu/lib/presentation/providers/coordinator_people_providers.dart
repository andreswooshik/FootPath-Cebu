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
