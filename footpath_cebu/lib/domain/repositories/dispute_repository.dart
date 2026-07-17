import 'package:footpath_cebu/domain/entities/dispute.dart';

/// Reads the dispute list (every dispute — the backend scopes access to the
/// coach/staff/admin roles).
abstract class DisputeReader {
  /// Returns all disputes, newest first, each with its full thread.
  Future<List<Dispute>> fetchDisputes();
}

/// Writes: flag a new dispute, or append to a thread. Split from the reader —
/// Interface Segregation, mirroring the attendance/injury repositories.
abstract class DisputeWriter {
  /// Flags a new dispute. `raised_by` is the signed-in user (server-forced).
  Future<Dispute> raiseDispute({
    required DisputeCategory category,
    required String summary,
    String? detail,
    String? subjectPlayerId,
  });

  /// Appends a response, optionally moving the dispute's status. Returns the
  /// updated dispute with its full thread.
  Future<Dispute> respondToDispute(
    String disputeId,
    String body, {
    DisputeStatus? statusChangeTo,
  });
}

/// Aggregate the concrete data sources implement.
abstract class DisputeRepository implements DisputeReader, DisputeWriter {}

/// Thrown when a dispute read or write cannot be completed.
class DisputeRepositoryException implements Exception {
  DisputeRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}
