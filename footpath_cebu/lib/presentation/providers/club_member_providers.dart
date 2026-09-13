import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/runtime_config.dart';
import 'package:footpath_cebu/data/repositories/api_club_member_repository.dart';
import 'package:footpath_cebu/domain/entities/club_member.dart';

final clubMembersProvider = FutureProvider.autoDispose
    .family<List<ClubMember>, ClubMemberRole>((ref, role) {
      if (useMockData) return _mockClubMembers(role);
      return ApiClubMemberRepository().fetch(role);
    });

Future<List<ClubMember>> _mockClubMembers(ClubMemberRole role) async {
  if (role == ClubMemberRole.coach) {
    return const [
      ClubMember(
        id: 'coach-1',
        name: 'Coach Reyes',
        role: ClubMemberRole.coach,
        roleDisplay: 'Coach',
        email: 'coach.reyes@example.com',
      ),
    ];
  }
  return const [
    ClubMember(
      id: 'guardian-1',
      name: 'Maria Santos',
      role: ClubMemberRole.guardian,
      roleDisplay: 'Guardian',
      email: 'maria.santos@example.com',
      linkedPlayers: ['Rhobert Ronaldo'],
    ),
  ];
}
