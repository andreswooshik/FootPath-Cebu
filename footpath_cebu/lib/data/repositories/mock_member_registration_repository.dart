import 'package:footpath_cebu/data/repositories/mock_club_member_repository.dart';
import 'package:footpath_cebu/domain/entities/club_member.dart';
import 'package:footpath_cebu/domain/entities/member_registration.dart';
import 'package:footpath_cebu/domain/repositories/member_registration_repository.dart';

class MockMemberRegistrationRepository implements MemberRegistrationRepository {
  MockMemberRegistrationRepository(this.members);
  final MockClubMemberRepository members;
  final _results = <String, MemberRegistrationResult>{};

  @override
  Future<MemberRegistrationResult> create(
    MemberAccountRole role,
    MemberRegistrationData data,
  ) async {
    final previous = _results[data.requestId];
    if (previous != null) {
      return MemberRegistrationResult(
        memberId: previous.memberId,
        coordinatorId: previous.coordinatorId,
        role: previous.role,
        name: previous.name,
        email: previous.email,
        replayed: true,
      );
    }
    final normalizedEmail = data.email.trim().toLowerCase();
    if (members.members.any(
      (member) => member.email.toLowerCase() == normalizedEmail,
    )) {
      throw const MemberRegistrationException(
        'An account with this email already exists.',
      );
    }
    final member = ClubMember(
      id: '${role.wire.toLowerCase()}-${members.members.length + 1}',
      name: data.name,
      role: role == MemberAccountRole.coach
          ? ClubMemberRole.coach
          : ClubMemberRole.guardian,
      roleDisplay: role.label,
      email: normalizedEmail,
      mobileNumber: data.mobileNumber,
    );
    members.addMember(member);
    final result = MemberRegistrationResult(
      memberId: member.id,
      coordinatorId: 'mock-coordinator',
      role: role,
      name: member.name,
      email: member.email,
      temporaryPassword: 'TempPass123',
    );
    _results[data.requestId] = result;
    return result;
  }
}
