import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:footpath_cebu/core/config/api_config.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';
import 'package:http/http.dart' as http;

/// Live implementation backed by the Django REST API, authenticated with the
/// signed-in user's Firebase ID token (same pattern as [ApiTrainingRepository]).
class ApiAttendanceRepository implements AttendanceRepository {
  static const _path = '/api/attendance/';

  @override
  Future<List<Attendance>> fetchAttendanceForPlayer(String playerId) async {
    final idToken = await _requireIdToken();

    final http.Response response;
    try {
      response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}$_path?player=$playerId'),
        headers: {'Authorization': 'Bearer $idToken'},
      );
    } catch (_) {
      throw AttendanceRepositoryException(
        'Could not reach the server. Is it running?',
      );
    }

    if (response.statusCode != 200) {
      throw AttendanceRepositoryException(
        'Request failed (${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body);
    final list = decoded is Map<String, dynamic>
        ? (decoded['results'] as List? ?? const [])
        : (decoded as List? ?? const []);

    final records = list
        .cast<Map<String, dynamic>>()
        .map(Attendance.fromJson)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return records;
  }

  // Live backend wiring for per-session attendance is the backend task's job.
  // The Attendance & Evaluation screen runs on MockAttendanceRepository; these
  // stubs only satisfy the AttendanceRepository interface so the app compiles.
  // Suggested endpoints: GET  {_path}?session=<id>
  //                      POST {_path}session/<id>/  body {"records": [...]}
  @override
  Future<List<Attendance>> fetchAttendanceForSession(String sessionId) {
    throw UnimplementedError(
      'fetchAttendanceForSession: pending backend wiring.',
    );
  }

  @override
  Future<List<Attendance>> saveSessionAttendance(
    String sessionId,
    List<Attendance> records,
  ) {
    throw UnimplementedError(
      'saveSessionAttendance: pending backend wiring.',
    );
  }

  Future<String> _requireIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw AttendanceRepositoryException('Not signed in.');
    }
    final token = await user.getIdToken();
    if (token == null) {
      throw AttendanceRepositoryException('Not signed in.');
    }
    return token;
  }
}
