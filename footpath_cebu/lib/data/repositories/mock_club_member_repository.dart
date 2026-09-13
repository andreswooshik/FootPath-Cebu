import 'package:footpath_cebu/domain/entities/club_member.dart';

class MockClubMemberRepository {
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
    ),
  ];

  Future<List<ClubMember>> fetch(ClubMemberRole role) async =>
      List.unmodifiable(members.where((member) => member.role == role));

  void addMember(ClubMember member) => members.add(member);

  void linkPlayer(ClubMember guardian, String playerName) {
    final index = members.indexWhere((member) => member.id == guardian.id);
    final updated = ClubMember(
      id: guardian.id,
      name: guardian.name,
      role: guardian.role,
      roleDisplay: guardian.roleDisplay,
      email: guardian.email,
      mobileNumber: guardian.mobileNumber,
      linkedPlayers: [...guardian.linkedPlayers, playerName],
    );
    if (index < 0) {
      members.add(updated);
    } else {
      members[index] = updated;
    }
  }
}
