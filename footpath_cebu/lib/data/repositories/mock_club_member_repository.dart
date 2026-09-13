import 'package:footpath_cebu/domain/entities/club_member.dart';
import 'package:footpath_cebu/domain/repositories/club_member_repository.dart';

class MockClubMemberRepository implements ClubMemberRepository {
  final List<ClubMember> members = [
    const ClubMember(
      id: 'coach-1',
      name: 'Coach Reyes',
      role: ClubMemberRole.coach,
      roleDisplay: 'Coach',
      email: 'coach.reyes@example.com',
    ),
    const ClubMember(
      id: 'guardian-1',
      name: 'Maria Santos',
      role: ClubMemberRole.guardian,
      roleDisplay: 'Guardian',
      email: 'maria.santos@example.com',
      mobileNumber: '+639171234567',
      linkedPlayers: ['Rhobert Ronaldo'],
      linkedPlayerIds: ['p1'],
    ),
  ];

  @override
  Future<List<ClubMember>> fetch(ClubMemberRole role) async =>
      List.unmodifiable(members.where((member) => member.role == role));

  void addMember(ClubMember member) => members.add(member);

  ClubMember? findMember(String id) {
    for (final member in members) {
      if (member.id == id) return member;
    }
    return null;
  }

  void removeMember(String id) =>
      members.removeWhere((member) => member.id == id);

  void unlinkPlayer(String playerId) {
    for (var index = 0; index < members.length; index++) {
      final member = members[index];
      final linkedIndex = member.linkedPlayerIds.indexOf(playerId);
      if (linkedIndex < 0) continue;
      final names = [...member.linkedPlayers]..removeAt(linkedIndex);
      final ids = [...member.linkedPlayerIds]..removeAt(linkedIndex);
      members[index] = ClubMember(
        id: member.id,
        name: member.name,
        role: member.role,
        roleDisplay: member.roleDisplay,
        email: member.email,
        mobileNumber: member.mobileNumber,
        linkedPlayers: names,
        linkedPlayerIds: ids,
      );
    }
  }

  void linkPlayer(ClubMember guardian, String playerId, String playerName) {
    final index = members.indexWhere((member) => member.id == guardian.id);
    final updated = ClubMember(
      id: guardian.id,
      name: guardian.name,
      role: guardian.role,
      roleDisplay: guardian.roleDisplay,
      email: guardian.email,
      mobileNumber: guardian.mobileNumber,
      linkedPlayers: [...guardian.linkedPlayers, playerName],
      linkedPlayerIds: [...guardian.linkedPlayerIds, playerId],
    );
    if (index < 0) {
      members.add(updated);
    } else {
      members[index] = updated;
    }
  }
}
