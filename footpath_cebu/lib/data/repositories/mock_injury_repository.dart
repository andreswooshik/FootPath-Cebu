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
      reviewStatus: InjuryReportStatus.confirmed,
      playerName: 'Rhobert Ronaldo',
      reporterName: 'Rhobert Ronaldo',
      reporterRole: 'PLAYER',
      canEditConfirmed: true,
      canArchive: false,
      canRequestStatusUpdate: true,
      occurredOn: DateTime(2026, 6, 20),
      notes: 'Twisted on landing. Cleared for light drills only.',
    ),
    InjuryRecord(
      id: 'i2',
      playerId: 'p1',
      description: 'Bruised knee',
      bodyPart: 'Right knee',
      status: InjuryStatus.recovered,
      reviewStatus: InjuryReportStatus.confirmed,
      playerName: 'Rhobert Ronaldo',
      reporterName: 'Coach Reyes',
      reporterRole: 'COACH',
      canEditConfirmed: true,
      canArchive: true,
      occurredOn: DateTime(2026, 5, 2),
      resolvedOn: DateTime(2026, 5, 16),
    ),
  ];
  int _nextId = 3;

  @override
  Future<List<InjuryRecord>> fetchInjuriesForPlayer(
    String playerId, {
    String? unlockToken,
  }) async {
    // Simulate network latency so loading states are exercised in the UI.
    await Future.delayed(const Duration(milliseconds: 300));
    final records = _records.where((r) => r.playerId == playerId).toList()
      ..sort((a, b) => b.occurredOn.compareTo(a.occurredOn));
    return List.unmodifiable(records);
  }

  @override
  Future<List<InjuryRecord>> fetchClubInjuries({
    bool includeArchived = false,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _records
        .where(
          (record) =>
              includeArchived ||
              record.reviewStatus != InjuryReportStatus.archived,
        )
        .toList(growable: false);
  }

  @override
  Future<List<InjuryPlayerOption>> fetchReportablePlayers() async => const [
    InjuryPlayerOption(
      id: 'p1',
      name: 'Rhobert Ronaldo',
      ageTier: 'DEVELOPMENT',
    ),
    InjuryPlayerOption(id: 'p2', name: 'Mika Santos', ageTier: 'FOUNDATION'),
  ];

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
        playerName: record.playerName.isEmpty
            ? 'Rhobert Ronaldo'
            : record.playerName,
        reviewStatus: InjuryReportStatus.pending,
        reporterName: 'Current user',
        reporterRole: 'PLAYER',
        canEditPending: true,
        canReview: true,
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
  Future<void> deleteInjury(InjuryRecord record) async {
    await Future.delayed(const Duration(milliseconds: 200));
    _records.removeWhere((r) => r.id == record.id);
  }

  @override
  Future<InjuryRecord> reviewInjury(
    String injuryId, {
    required bool confirm,
    String rejectionReason = '',
  }) async {
    final index = _records.indexWhere((record) => record.id == injuryId);
    if (index < 0) throw InjuryRepositoryException('Injury not found.');
    final updated = _replace(
      _records[index],
      reviewStatus: confirm
          ? InjuryReportStatus.confirmed
          : InjuryReportStatus.rejected,
      rejectionReason: rejectionReason,
      canEditPending: false,
      canReview: false,
      canEditConfirmed: confirm,
      canArchive: confirm && _records[index].status == InjuryStatus.recovered,
      canRequestStatusUpdate: confirm,
    );
    _records[index] = updated;
    return updated;
  }

  @override
  Future<InjuryRecord> archiveInjury(String injuryId) async {
    final index = _records.indexWhere((record) => record.id == injuryId);
    if (index < 0) throw InjuryRepositoryException('Injury not found.');
    final updated = _replace(
      _records[index],
      reviewStatus: InjuryReportStatus.archived,
      canArchive: false,
      canEditConfirmed: false,
      canRequestStatusUpdate: false,
    );
    _records[index] = updated;
    return updated;
  }

  @override
  Future<InjuryStatusUpdate> requestStatusUpdate(
    InjuryRecord injury,
    InjuryStatusUpdateDraft draft,
  ) async {
    final index = _records.indexWhere((record) => record.id == injury.id);
    if (index < 0) throw InjuryRepositoryException('Injury not found.');
    final update = InjuryStatusUpdate(
      id: 'update-${injury.id}',
      proposedStatus: draft.proposedStatus,
      proposedResolvedOn: draft.proposedResolvedOn,
      notes: draft.notes,
      reviewStatus: InjuryUpdateReviewStatus.pending,
      submittedByName: 'Current user',
      submittedByRole: 'PLAYER',
      createdAt: DateTime.now(),
    );
    _records[index] = _replace(
      injury,
      pendingStatusUpdate: update,
      canRequestStatusUpdate: false,
    );
    return update;
  }

  @override
  Future<InjuryRecord> reviewStatusUpdate(
    String injuryId,
    String updateId, {
    required bool approve,
    String rejectionReason = '',
  }) async {
    final index = _records.indexWhere((record) => record.id == injuryId);
    if (index < 0) throw InjuryRepositoryException('Injury not found.');
    final record = _records[index];
    final update = record.pendingStatusUpdate;
    final updated = _replace(
      record,
      status: approve && update != null ? update.proposedStatus : record.status,
      resolvedOn: approve ? update?.proposedResolvedOn : record.resolvedOn,
      clearPendingStatusUpdate: true,
      canArchive: approve
          ? update?.proposedStatus == InjuryStatus.recovered
          : record.canArchive,
      canRequestStatusUpdate:
          !approve || update?.proposedStatus != InjuryStatus.recovered,
    );
    _records[index] = updated;
    return updated;
  }

  InjuryRecord _replace(
    InjuryRecord record, {
    InjuryStatus? status,
    DateTime? resolvedOn,
    InjuryReportStatus? reviewStatus,
    String? rejectionReason,
    InjuryStatusUpdate? pendingStatusUpdate,
    bool clearPendingStatusUpdate = false,
    bool? canEditPending,
    bool? canReview,
    bool? canEditConfirmed,
    bool? canArchive,
    bool? canRequestStatusUpdate,
  }) => InjuryRecord(
    id: record.id,
    playerId: record.playerId,
    playerName: record.playerName,
    description: record.description,
    status: status ?? record.status,
    occurredOn: record.occurredOn,
    bodyPart: record.bodyPart,
    resolvedOn: resolvedOn ?? record.resolvedOn,
    notes: record.notes,
    reviewStatus: reviewStatus ?? record.reviewStatus,
    reporterName: record.reporterName,
    reporterRole: record.reporterRole,
    rejectionReason: rejectionReason ?? record.rejectionReason,
    reviewedAt: record.reviewedAt,
    archivedAt: record.archivedAt,
    pendingStatusUpdate: clearPendingStatusUpdate
        ? null
        : (pendingStatusUpdate ?? record.pendingStatusUpdate),
    canEditPending: canEditPending ?? record.canEditPending,
    canReview: canReview ?? record.canReview,
    canEditConfirmed: canEditConfirmed ?? record.canEditConfirmed,
    canArchive: canArchive ?? record.canArchive,
    canRequestStatusUpdate:
        canRequestStatusUpdate ?? record.canRequestStatusUpdate,
    createdAt: record.createdAt,
    updatedAt: record.updatedAt,
  );
}
