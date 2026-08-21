import 'dart:convert';

import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';

/// Live implementation backed by the Django REST API, authenticated with the
/// signed-in user's Firebase ID token (same pattern as [ApiTrainingRepository]).
class ApiAttendanceRepository implements AttendanceRepository {
  ApiAttendanceRepository({this.unlockTokenFor, AuthenticatedApiClient? api})
    : _api = api ?? AuthenticatedApiClient.shared;

  final String? Function(String playerId)? unlockTokenFor;
  final AuthenticatedApiClient _api;

  static const _path = '/api/attendance/';

  @override
  Future<List<Attendance>> fetchAttendanceForPlayer(
    String playerId, {
    String? unlockToken,
  }) async {
    final playerUnlock = unlockToken ?? unlockTokenFor?.call(playerId);
    try {
      final response = await _api.get(
        '$_path?player=$playerId',
        headers: {
          if (playerUnlock != null && playerUnlock.isNotEmpty)
            'X-Player-Unlock': playerUnlock,
        },
      );
      return _decodeRecords(response.body)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } on ApiNetworkException catch (error) {
      throw AttendanceNetworkException(error.message);
    } on ApiHttpException catch (error) {
      throw AttendanceRepositoryException(
        error.message,
        statusCode: error.statusCode,
      );
    } on ApiException catch (error) {
      throw AttendanceRepositoryException(error.message);
    }
  }

  @override
  Future<List<Attendance>> fetchAttendanceForSession(String sessionId) async {
    try {
      final response = await _api.get('${_path}session/$sessionId/');
      return _decodeRecords(response.body);
    } on ApiNetworkException catch (error) {
      throw AttendanceNetworkException(error.message);
    } on ApiHttpException catch (error) {
      throw AttendanceRepositoryException(
        error.message,
        statusCode: error.statusCode,
      );
    } on ApiException catch (error) {
      throw AttendanceRepositoryException(error.message);
    }
  }

  @override
  Future<List<Attendance>> saveSessionAttendance(
    String sessionId,
    List<Attendance> records,
  ) async {
    try {
      final response = await _api.post(
        '${_path}session/$sessionId/',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'records': records.map((r) => r.toJson()).toList()}),
      );
      // The server echoes the session's saved records back.
      return _decodeRecords(response.body);
    } on ApiNetworkException catch (error) {
      throw AttendanceNetworkException(error.message);
    } on ApiHttpException catch (error) {
      throw AttendanceRepositoryException(
        error.message,
        statusCode: error.statusCode,
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
}
