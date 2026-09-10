import 'dart:convert';

import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/data/local/attendance_request_id.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';

/// Live implementation backed by the Django REST API, authenticated with the
/// signed-in user's Firebase ID token (same pattern as [ApiTrainingRepository]).
class ApiAttendanceRepository
    implements AttendanceRepository, VersionedSessionAttendanceWriter {
  ApiAttendanceRepository({this.unlockTokenFor, AuthenticatedApiClient? api})
    : _api = api ?? AuthenticatedApiClient.shared;

  final String? Function(String playerId)? unlockTokenFor;
  final AuthenticatedApiClient _api;

  static const _path = '/api/attendance/';
  final Map<String, int> _sessionRevisions = {};

  @override
  Future<List<Attendance>> fetchAttendanceForPlayer(
    String playerId, {
    String? unlockToken,
  }) async {
    final playerUnlock = unlockToken ?? unlockTokenFor?.call(playerId);
    try {
      final records = await _api.getList(
        '$_path?player=$playerId',
        headers: {
          if (playerUnlock != null && playerUnlock.isNotEmpty)
            'X-Player-Unlock': playerUnlock,
        },
      );
      return records.map(Attendance.fromJson).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } on ApiNetworkException catch (error) {
      throw AttendanceNetworkException(error.message);
    } on ApiHttpException catch (error) {
      throw AttendanceRepositoryException(
        error.message,
        statusCode: error.statusCode,
        code: error.code,
        details: error.details,
      );
    } on ApiException catch (error) {
      throw AttendanceRepositoryException(error.message);
    }
  }

  @override
  Future<List<Attendance>> fetchAttendanceForSession(String sessionId) async {
    try {
      final response = await _api.get('${_path}session/$sessionId/?limit=500');
      _captureRevision(sessionId, response.headers);
      return _decodeRecords(response.body);
    } on ApiNetworkException catch (error) {
      throw AttendanceNetworkException(error.message);
    } on ApiHttpException catch (error) {
      throw AttendanceRepositoryException(
        error.message,
        statusCode: error.statusCode,
        code: error.code,
        details: error.details,
      );
    } on ApiException catch (error) {
      throw AttendanceRepositoryException(error.message);
    }
  }

  @override
  Future<List<Attendance>> saveSessionAttendance(
    String sessionId,
    List<Attendance> records,
  ) => saveVersionedSessionAttendance(
    sessionId,
    records,
    requestId: AttendanceRequestId.create(),
    expectedRevision: revisionForSession(sessionId),
  );

  @override
  int? revisionForSession(String sessionId) => _sessionRevisions[sessionId];

  @override
  Future<List<Attendance>> saveVersionedSessionAttendance(
    String sessionId,
    List<Attendance> records, {
    required String requestId,
    int? expectedRevision,
  }) async {
    try {
      final response = await _api.post(
        '${_path}session/$sessionId/?limit=500',
        headers: {
          'Content-Type': 'application/json',
          'Idempotency-Key': requestId,
          if (expectedRevision != null) 'If-Match': '"$expectedRevision"',
        },
        body: jsonEncode({'records': records.map((r) => r.toJson()).toList()}),
      );
      _captureRevision(sessionId, response.headers);
      // The server echoes the session's saved records back.
      return _decodeRecords(response.body);
    } on ApiNetworkException catch (error) {
      throw AttendanceNetworkException(error.message);
    } on ApiHttpException catch (error) {
      throw AttendanceRepositoryException(
        error.message,
        statusCode: error.statusCode,
        code: error.code,
        details: error.details,
      );
    } on ApiException catch (error) {
      throw AttendanceRepositoryException(error.message);
    }
  }

  List<Attendance> _decodeRecords(String body) {
    final decoded = jsonDecode(body);
    final list = decoded is Map<String, dynamic>
        ? (decoded['results'] as List? ?? const [])
        : (decoded as List? ?? const []);
    return list.cast<Map<String, dynamic>>().map(Attendance.fromJson).toList();
  }

  void _captureRevision(String sessionId, Map<String, String> headers) {
    final raw = headers['x-attendance-revision'];
    final revision = int.tryParse(raw ?? '');
    if (revision != null && revision >= 0) {
      _sessionRevisions[sessionId] = revision;
    }
  }
}
