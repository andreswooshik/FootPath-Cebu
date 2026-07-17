import 'package:footpath_cebu/domain/entities/dispute.dart';
import 'package:footpath_cebu/domain/repositories/dispute_repository.dart';

/// In-memory disputes for UI development without a backend. Instance state so
/// tests get a clean slate while the app (one instance per run) sees edits
/// persist across screens.
class MockDisputeRepository implements DisputeRepository {
  final List<Dispute> _disputes = [
    Dispute(
      id: 'd1',
      category: DisputeCategory.attendance,
      status: DisputeStatus.underReview,
      summary: 'Attendance mark disputed',
      detail: 'Player claims they were present on July 10.',
      raisedByName: 'Coach Cruz',
      subjectPlayerId: 'p1',
      subjectPlayerName: 'Rhobert Ronaldo',
      createdAt: DateTime(2026, 7, 11, 9),
      updatedAt: DateTime(2026, 7, 12, 14),
      responses: [
        DisputeResponse(
          id: 'r1',
          body: 'Checking the sign-in sheet with the P.E. department.',
          createdAt: DateTime(2026, 7, 12, 14),
          authorName: 'Staff Reyes',
          authorRole: 'SCHOOL_STAFF',
          statusChangeTo: DisputeStatus.underReview,
        ),
      ],
    ),
  ];
  int _nextDispute = 2;
  int _nextResponse = 2;

  @override
  Future<List<Dispute>> fetchDisputes() async {
    // Simulate network latency so loading states are exercised in the UI.
    await Future.delayed(const Duration(milliseconds: 300));
    final disputes = [..._disputes]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(disputes);
  }

  @override
  Future<Dispute> raiseDispute({
    required DisputeCategory category,
    required String summary,
    String? detail,
    String? subjectPlayerId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final now = DateTime.now();
    final dispute = Dispute(
      id: 'd${_nextDispute++}',
      category: category,
      status: DisputeStatus.open,
      summary: summary,
      detail: detail,
      raisedByName: 'Coach Cruz',
      subjectPlayerId: subjectPlayerId,
      createdAt: now,
      updatedAt: now,
    );
    _disputes.add(dispute);
    return dispute;
  }

  @override
  Future<Dispute> respondToDispute(
    String disputeId,
    String body, {
    DisputeStatus? statusChangeTo,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final index = _disputes.indexWhere((d) => d.id == disputeId);
    if (index == -1) {
      throw DisputeRepositoryException('Dispute not found.');
    }
    final existing = _disputes[index];
    final now = DateTime.now();
    final updated = Dispute(
      id: existing.id,
      category: existing.category,
      status: statusChangeTo ?? existing.status,
      summary: existing.summary,
      detail: existing.detail,
      raisedByName: existing.raisedByName,
      subjectPlayerId: existing.subjectPlayerId,
      subjectPlayerName: existing.subjectPlayerName,
      createdAt: existing.createdAt,
      updatedAt: now,
      responses: [
        ...existing.responses,
        DisputeResponse(
          id: 'r${_nextResponse++}',
          body: body,
          createdAt: now,
          authorName: 'Coach Cruz',
          authorRole: 'COACH',
          statusChangeTo: statusChangeTo,
        ),
      ],
    );
    _disputes[index] = updated;
    return updated;
  }
}
