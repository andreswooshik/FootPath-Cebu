import 'package:footpath_cebu/data/repositories/mock_club_member_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_player_repository.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/club_member.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_registration.dart';
import 'package:footpath_cebu/domain/repositories/player_registration_repository.dart';

class MockPlayerRegistrationRepository implements PlayerRegistrationRepository {
  MockPlayerRegistrationRepository(this.members, this.players);
  final MockClubMemberRepository members;
  final MockPlayerRepository players;
  final _results = <String, PlayerRegistrationResult>{};

  @override
  Future<void> checkGuardian(GuardianRegistrationData guardian) async {
    final phone = guardian.mobileNumber
        .replaceAll(RegExp(r'[^0-9]'), '')
        .replaceFirst(RegExp(r'^0'), '63');
    for (final member in members.members) {
      if (member.email.toLowerCase() == guardian.email.trim().toLowerCase() ||
          (member.mobileNumber.isNotEmpty &&
              member.mobileNumber.replaceAll('+', '') == phone)) {
        throw PlayerRegistrationException(
          'A guardian with this email or mobile number already exists.',
          existingGuardianId: member.id,
        );
      }
    }
  }

  @override
  Future<PlayerRegistrationResult> register(
    PlayerRegistrationDraft draft,
  ) async {
    if (_results.containsKey(draft.requestId)) {
      return _results[draft.requestId]!;
    }
    if (draft.existingGuardian == null) {
      await checkGuardian(draft.guardian);
    }
    final guardian =
        draft.existingGuardian ??
        ClubMember(
          id: 'guardian-${draft.requestId}',
          name: draft.guardian.name,
          role: ClubMemberRole.guardian,
          roleDisplay: 'Guardian',
          email: draft.guardian.email,
          mobileNumber: draft.guardian.mobileNumber,
        );
    final now = DateTime.now();
    final dob = draft.player.dateOfBirth!;
    final age =
        now.year -
        dob.year -
        (now.month < dob.month || (now.month == dob.month && now.day < dob.day)
            ? 1
            : 0);
    final player = Player(
      id: 'player-${draft.requestId}',
      name: draft.player.name,
      age: age,
      classYear: '',
      ageTier: AgeTierInfo.forAge(age) ?? AgeTier.development,
      eligibility: EligibilityStatus.pending,
      ratings: const PlayerRatings(
        pace: 0,
        shooting: 0,
        passing: 0,
        dribbling: 0,
        defending: 0,
        physical: 0,
      ),
    );
    players.addRegisteredPlayer(player);
    members.linkPlayer(guardian, player.name);
    final result = PlayerRegistrationResult(
      playerId: player.id,
      guardianId: guardian.id,
      coordinatorId: 'mock-coordinator',
      guardianCreated: draft.existingGuardian == null,
      guardianEmail: guardian.email,
    );
    _results[draft.requestId] = result;
    return result;
  }
}
