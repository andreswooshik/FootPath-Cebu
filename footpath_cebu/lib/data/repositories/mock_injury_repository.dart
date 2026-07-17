import 'package:footpath_cebu/domain/entities/injury_record.dart';
import 'package:footpath_cebu/domain/repositories/injury_repository.dart';

/// In-memory injury history for UI development without a backend. Seeded for
/// the signed-in player (p1, [MockPlayerRepository.fetchMyProfile]). Instance
/// state (not static) so each test gets a clean slate while the app — which
/// builds one instance per run — still sees edits persist across screens.
class MockInjuryRepository implements InjuryRepository {
  final List<InjuryRecord> _records = [
    InjuryRecord(
      id: 'i1',
      playerId: 'p1',
      description: 'Sprained ankle',
      bodyPart: 'Left ankle',
      status: InjuryStatus.recovering,
      occurredOn: DateTime(2026, 6, 20),
      notes: 'Twisted on landing. Cleared for light drills only.',
    ),
    InjuryRecord(
      id: 'i2',
      playerId: 'p1',
      description: 'Bruised knee',
      bodyPart: 'Right knee',
      status: InjuryStatus.recovered,
      occurredOn: DateTime(2026, 5, 2),
      resolvedOn: DateTime(2026, 5, 16),
    ),
  ];
  int _nextId = 3;

  @override
  Future<List<InjuryRecord>> fetchInjuriesForPlayer(String playerId) async {
    // Simulate network latency so loading states are exercised in the UI.
    await Future.delayed(const Duration(milliseconds: 300));
    final records = _records.where((r) => r.playerId == playerId).toList()
      ..sort((a, b) => b.occurredOn.compareTo(a.occurredOn));
    return List.unmodifiable(records);
  }

  @override
  Future<InjuryRecord> saveInjury(InjuryRecord record) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (record.id == null) {
      final created = InjuryRecord(
        id: 'i${_nextId++}',
        playerId: record.playerId,
        description: record.description,
        status: record.status,
        occurredOn: record.occurredOn,
        bodyPart: record.bodyPart,
        resolvedOn: record.resolvedOn,
        notes: record.notes,
      );
      _records.add(created);
      return created;
    }
    final index = _records.indexWhere((r) => r.id == record.id);
    if (index == -1) {
      throw InjuryRepositoryException('Injury record not found.');
    }
    _records[index] = record;
    return record;
  }

  @override
  Future<void> deleteInjury(String injuryId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    _records.removeWhere((r) => r.id == injuryId);
  }
}
