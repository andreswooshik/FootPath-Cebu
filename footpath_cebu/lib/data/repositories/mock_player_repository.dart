import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';

/// In-memory squad roster for UI development without a backend.
class MockPlayerRepository implements PlayerRepository {
  static final List<Player> _squad = [
    const Player(
      id: 'p1',
      name: 'Rhobert Ronaldo',
      age: 16,
      classYear: 'Class of 2026',
      ageTier: AgeTier.pathway,
      position: PlayerPosition.striker,
      eligibility: EligibilityStatus.eligible,
      ratings: PlayerRatings(
        pace: 99, shooting: 97, passing: 88, dribbling: 95, defending: 45,
        physical: 90,
      ),
    ),
    const Player(
      id: 'p2',
      name: 'Ralf Andre Messi',
      age: 15,
      classYear: 'Class of 2025',
      ageTier: AgeTier.development,
      position: PlayerPosition.attackingMidfielder,
      eligibility: EligibilityStatus.academicWarning,
      ratings: PlayerRatings(
        pace: 91, shooting: 92, passing: 96, dribbling: 99, defending: 40,
        physical: 72,
      ),
    ),
    const Player(
      id: 'p3',
      name: 'Reiner Neymar',
      age: 15,
      classYear: 'Class of 2027',
      ageTier: AgeTier.development,
      position: PlayerPosition.leftWinger,
      eligibility: EligibilityStatus.eligible,
      ratings: PlayerRatings(
        pace: 95, shooting: 89, passing: 90, dribbling: 96, defending: 38,
        physical: 68,
      ),
    ),
    const Player(
      id: 'p4',
      name: 'Kevin De Bofill',
      age: 17,
      classYear: 'Class of 2025',
      ageTier: AgeTier.pathway,
      position: PlayerPosition.centralMidfielder,
      eligibility: EligibilityStatus.eligible,
      ratings: PlayerRatings(
        pace: 78, shooting: 88, passing: 93, dribbling: 87, defending: 66,
        physical: 79,
      ),
    ),
    const Player(
      id: 'p5',
      name: 'Virgil Van Cortez',
      age: 18,
      classYear: 'Class of 2024',
      ageTier: AgeTier.pathway,
      position: PlayerPosition.centerBack,
      eligibility: EligibilityStatus.pending,
      ratings: PlayerRatings(
        pace: 81, shooting: 60, passing: 71, dribbling: 72, defending: 95,
        physical: 92,
      ),
    ),
    const Player(
      id: 'p6',
      name: 'Trent Alexander Cruz',
      age: 14,
      classYear: 'Class of 2028',
      ageTier: AgeTier.development,
      position: PlayerPosition.rightBack,
      eligibility: EligibilityStatus.eligible,
      ratings: PlayerRatings(
        pace: 84, shooting: 66, passing: 86, dribbling: 80, defending: 82,
        physical: 76,
      ),
    ),
    const Player(
      id: 'p7',
      name: 'Gianluigi Dela Cruz',
      age: 16,
      classYear: 'Class of 2026',
      ageTier: AgeTier.pathway,
      position: PlayerPosition.goalkeeper,
      eligibility: EligibilityStatus.notEligible,
      ratings: PlayerRatings(
        pace: 55, shooting: 22, passing: 74, dribbling: 60, defending: 48,
        physical: 88,
      ),
    ),
    const Player(
      id: 'p8',
      name: 'Jude Belino',
      age: 13,
      classYear: 'Class of 2029',
      ageTier: AgeTier.development,
      position: PlayerPosition.centralMidfielder,
      eligibility: EligibilityStatus.eligible,
      ratings: PlayerRatings(
        pace: 82, shooting: 84, passing: 85, dribbling: 88, defending: 70,
        physical: 74,
      ),
    ),
    const Player(
      id: 'p9',
      name: 'Lamine Yamashita',
      age: 11,
      classYear: 'Class of 2031',
      ageTier: AgeTier.foundation,
      position: PlayerPosition.rightWinger,
      eligibility: EligibilityStatus.eligible,
      ratings: PlayerRatings(
        pace: 76, shooting: 62, passing: 68, dribbling: 79, defending: 30,
        physical: 48,
      ),
    ),
    const Player(
      id: 'p10',
      name: 'Pedri Villanueva',
      age: 12,
      classYear: 'Class of 2030',
      ageTier: AgeTier.foundation,
      // Freshly registered by the admin — no position until the coach has
      // evaluated them. Exercises the "assign" (rather than "change") flow.
      position: null,
      eligibility: EligibilityStatus.pending,
      ratings: PlayerRatings(
        pace: 64, shooting: 55, passing: 74, dribbling: 71, defending: 42,
        physical: 45,
      ),
    ),
  ];

  @override
  Future<List<Player>> fetchSquad() async {
    // Simulate network latency so loading states are exercised in the UI.
    await Future.delayed(const Duration(milliseconds: 500));
    return List.unmodifiable(_squad);
  }

  @override
  Future<Player> fetchMyProfile() async {
    await Future.delayed(const Duration(milliseconds: 500));
    // Stand-in for the signed-in player during UI development.
    return _squad.first;
  }

  @override
  Future<List<Player>> fetchLinkedPlayers() async {
    await Future.delayed(const Duration(milliseconds: 500));
    // Stand-in for a guardian's two linked children.
    return List.unmodifiable(_squad.where((p) => p.id == 'p2' || p.id == 'p3'));
  }

  @override
  Future<Player> savePosition(String playerId, PlayerPosition position) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final index = _squad.indexWhere((p) => p.id == playerId);
    if (index == -1) {
      throw PlayerRepositoryException('No such player.');
    }
    // Mutate in place so the change survives a later fetch, mirroring a real
    // backend write.
    final updated = _squad[index].copyWith(position: position);
    _squad[index] = updated;
    return updated;
  }

  @override
  Future<Player> saveAssessment(String playerId, PlayerRatings ratings) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final index = _squad.indexWhere((p) => p.id == playerId);
    if (index == -1) {
      throw PlayerRepositoryException('No such player.');
    }
    // Mutate in place so the change survives a later fetch, mirroring a real
    // backend write.
    final updated = _squad[index].copyWith(ratings: ratings);
    _squad[index] = updated;
    return updated;
  }
}
