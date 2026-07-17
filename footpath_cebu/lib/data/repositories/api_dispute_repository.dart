import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:footpath_cebu/core/config/api_config.dart';
import 'package:footpath_cebu/domain/entities/dispute.dart';
import 'package:footpath_cebu/domain/repositories/dispute_repository.dart';
import 'package:http/http.dart' as http;

/// Live implementation backed by the Django REST API, authenticated with the
/// signed-in coach's Firebase ID token (same pattern as
/// [ApiInjuryRepository]).
class ApiDisputeRepository implements DisputeRepository {
  static const _path = '/api/disputes/';

  @override
  Future<List<Dispute>> fetchDisputes() async {
    final response = await _send(
      (token) => http.get(
        Uri.parse('${ApiConfig.baseUrl}$_path'),
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
    if (response.statusCode != 200) {
      throw DisputeRepositoryException(
        'Request failed (${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body);
    final list = decoded is Map<String, dynamic>
        ? (decoded['results'] as List? ?? const [])
        : (decoded as List? ?? const []);
    return list.cast<Map<String, dynamic>>().map(Dispute.fromJson).toList();
  }

  @override
  Future<Dispute> raiseDispute({
    required DisputeCategory category,
    required String summary,
    String? detail,
    String? subjectPlayerId,
  }) async {
    final response = await _send(
      (token) => http.post(
        Uri.parse('${ApiConfig.baseUrl}$_path'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'category': category.wire,
          'summary': summary,
          'detail': ?detail,
          'subjectPlayerId': ?subjectPlayerId,
        }),
      ),
    );
    if (response.statusCode != 201) {
      throw DisputeRepositoryException(
        'Could not raise the dispute (${response.statusCode}).',
      );
    }
    return Dispute.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  @override
  Future<Dispute> respondToDispute(
    String disputeId,
    String body, {
    DisputeStatus? statusChangeTo,
  }) async {
    final response = await _send(
      (token) => http.post(
        Uri.parse('${ApiConfig.baseUrl}$_path$disputeId/responses/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'body': body,
          if (statusChangeTo != null) 'statusChangeTo': statusChangeTo.wire,
        }),
      ),
    );
    if (response.statusCode != 201) {
      throw DisputeRepositoryException(
        'Could not post the response (${response.statusCode}).',
      );
    }
    return Dispute.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Runs one authenticated request, translating connection-level failures
  /// into [DisputeRepositoryException].
  Future<http.Response> _send(
    Future<http.Response> Function(String idToken) request,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw DisputeRepositoryException('Not signed in.');
    }
    final token = await user.getIdToken();
    if (token == null) {
      throw DisputeRepositoryException('Not signed in.');
    }
    try {
      return await request(token);
    } catch (_) {
      throw DisputeRepositoryException(
        'Could not reach the server. Is it running?',
      );
    }
  }
}
