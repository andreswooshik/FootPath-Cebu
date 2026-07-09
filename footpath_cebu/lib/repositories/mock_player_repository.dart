import '../models/player.dart';
import 'player_repository.dart';

/// In-memory squad roster for UI development without a backend.
class MockPlayerRepository implements PlayerRepository {
  static final List<Player> _squad = [
    const Player(
      id: 'p1',
      name: 'Rhobert Ronaldo',
      age: 16,
      classYear: 'Class of 2026',
      ageTier: 'Pathway',
      position: 'ST',
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
      ageTier: 'Development',
      position: 'CAM',
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
      ageTier: 'Development',
      position: 'LW',
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
      ageTier: 'Pathway',
      position: 'CM',
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
      ageTier: 'Pathway',
      position: 'CB',
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
      ageTier: 'Development',
      position: 'RB',
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
      ageTier: 'Pathway',
      position: 'GK',
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
      ageTier: 'Development',
      position: 'CM',
      eligibility: EligibilityStatus.eligible,
      ratings: PlayerRatings(
        pace: 82, shooting: 84, passing: 85, dribbling: 88, defending: 70,
        physical: 74,
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
}
