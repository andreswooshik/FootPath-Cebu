import 'package:footpath_cebu/data/repositories/mock_club_member_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_player_repository.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/club_member.dart';
import 'package:footpath_cebu/domain/entities/coordinator_person.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/domain/repositories/coordinator_people_repository.dart';

class MockCoordinatorPeopleRepository implements CoordinatorPeopleRepository {
  MockCoordinatorPeopleRepository(this.members, this.players);

  final MockClubMemberRepository members;
  final MockPlayerRepository players;

  @override
  Future<CoordinatorPersonDetails> fetchDetails(
    CoordinatorPersonRole role,
    String id,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (role == CoordinatorPersonRole.player) {
      final player = players.findPlayer(id);
      if (player == null) throw _notFound();
      final guardians = members.members
          .where(
            (member) =>
                member.role == ClubMemberRole.guardian &&
                member.linkedPlayerIds.contains(id),
          )
          .map(
            (member) => CoordinatorPersonReference(
              id: member.id,
              name: member.name,
              email: member.email,
              mobileNumber: member.mobileNumber,
            ),
          )
          .toList(growable: false);
      final names = _names(player.name);
      return CoordinatorPersonDetails(
        id: player.id,
        role: role,
        firstName: names.$1,
        middleInitial: names.$2,
        lastName: names.$3,
        name: player.name,
        email: '',
        mobileNumber: '',
        age: player.age,
        classYear: player.classYear,
        ageTier: player.ageTier.name.toUpperCase(),
        ageTierDisplay: player.ageTier.label,
        position: player.position?.code,
        linkedPeople: guardians,
      );
    }

    final member = members.findMember(id);
    final expectedRole = role == CoordinatorPersonRole.guardian
        ? ClubMemberRole.guardian
        : ClubMemberRole.coach;
    if (member == null || member.role != expectedRole) throw _notFound();
    final names = _names(member.name);
    return CoordinatorPersonDetails(
      id: member.id,
      role: role,
      firstName: names.$1,
      middleInitial: names.$2,
      lastName: names.$3,
      name: member.name,
      email: member.email,
      mobileNumber: member.mobileNumber,
      linkedPeople: role == CoordinatorPersonRole.guardian
          ? member.linkedPlayerIds
                .map((playerId) {
                  final player = players.findPlayer(playerId);
                  return CoordinatorPersonReference(
                    id: playerId,
                    name: player?.name ?? 'Player unavailable',
                  );
                })
                .toList(growable: false)
          : const [],
    );
  }

  @override
  Future<void> deletePerson(CoordinatorPersonRole role, String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (role == CoordinatorPersonRole.player) {
      if (players.findPlayer(id) == null) throw _notFound();
      players.removePlayer(id);
      members.unlinkPlayer(id);
      return;
    }
    final member = members.findMember(id);
    if (member == null) throw _notFound();
    if (role == CoordinatorPersonRole.guardian &&
        member.linkedPlayerIds.isNotEmpty) {
      final count = member.linkedPlayerIds.length;
      throw CoordinatorPeopleRepositoryException(
        'This guardian still has $count linked ${count == 1 ? 'player' : 'players'}. '
        'Reassign or remove them before deleting this account.',
      );
    }
    members.removeMember(id);
  }

  CoordinatorPeopleRepositoryException _notFound() =>
      const CoordinatorPeopleRepositoryException(
        'This person is no longer available.',
      );

  (String, String, String) _names(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return (parts.first, '', '');
    return (parts.first, '', parts.sublist(1).join(' '));
  }
}
