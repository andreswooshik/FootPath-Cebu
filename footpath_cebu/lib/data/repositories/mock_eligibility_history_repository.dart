import 'package:footpath_cebu/domain/entities/eligibility_change.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/eligibility_history_repository.dart';

/// In-memory eligibility history for UI development without a backend. Seeded
/// for the signed-in player (p1, [MockPlayerRepository.fetchMyProfile]) and the
/// mock guardian's linked children (p2/p3). `changedBy` carries the role label,
/// matching what the live server exposes to families.
class MockEligibilityHistoryRepository implements EligibilityHistoryRepository {
  static final List<EligibilityChange> _records = [
    EligibilityChange(
      id: 'e1',
      oldStatus: null,
      newStatus: EligibilityStatus.pending,
      changedAt: DateTime(2026, 5, 4, 9, 30),
      changedBy: 'System',
    ),
    EligibilityChange(
      id: 'e2',
      oldStatus: EligibilityStatus.pending,
      newStatus: EligibilityStatus.eligible,
      changedAt: DateTime(2026, 5, 20, 14, 5),
      changedBy: 'School Staff',
    ),
    EligibilityChange(
      id: 'e3',
      oldStatus: EligibilityStatus.eligible,
      newStatus: EligibilityStatus.academicWarning,
      changedAt: DateTime(2026, 6, 28, 11, 45),
      changedBy: 'School Staff',
    ),
    EligibilityChange(
      id: 'e4',
      oldStatus: EligibilityStatus.academicWarning,
      newStatus: EligibilityStatus.eligible,
      changedAt: DateTime(2026, 7, 12, 10, 15),
      changedBy: 'School Staff',
    ),
  ];

  /// Every mock player shares the same plausible timeline — enough to build
  /// and style the history UI for player and guardian views alike.
  @override
  Future<List<EligibilityChange>> fetchHistoryForPlayer(
    String playerId,
  ) async {
    // Simulate network latency so loading states are exercised in the UI.
    await Future.delayed(const Duration(milliseconds: 300));
    final records = List.of(_records)
      ..sort((a, b) => b.changedAt.compareTo(a.changedAt));
    return List.unmodifiable(records);
  }
}
