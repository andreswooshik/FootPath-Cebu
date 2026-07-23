import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/domain/entities/player_progress.dart';
import 'package:footpath_cebu/domain/repositories/progress_repository.dart';

/// In-memory squad progress for UI development without a backend.
class MockProgressRepository implements ProgressRepository {
  @override
  Future<List<PlayerProgress>> fetchSquadProgress() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return const [
      PlayerProgress(
        id: 'p1', name: 'Miguel Santos',
        position: PlayerPosition.striker, ageTier: AgeTier.pathway,
        present: 14, absent: 1, excused: 1, avgEffort: 86,
      ),
      PlayerProgress(
        id: 'p2', name: 'Carlos Dela Cruz',
        position: PlayerPosition.goalkeeper, ageTier: AgeTier.development,
        present: 12, absent: 3, excused: 0, avgEffort: 78,
      ),
      PlayerProgress(
        id: 'p3', name: 'Rafael Lim',
        position: PlayerPosition.centralMidfielder, ageTier: AgeTier.foundation,
        present: 9, absent: 5, excused: 2, avgEffort: 64,
      ),
      PlayerProgress(
        id: 'p4', name: 'New Signing',
        position: null, ageTier: AgeTier.development,
        present: 0, absent: 0, excused: 0, avgEffort: null,
      ),
    ];
  }
}
