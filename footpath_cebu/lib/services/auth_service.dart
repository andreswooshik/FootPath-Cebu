import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// Thrown when Firebase accepts the credentials but the backend rejects the
/// account (e.g. a Firebase user that was never provisioned by an Admin).
class BackendAuthException implements Exception {
  BackendAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthService {
  /// Signs in with Firebase, then verifies the ID token against the Django
  /// backend. Returns the user profile (email, role, ...) from /api/auth/me/.
  Future<Map<String, dynamic>> signInAndFetchProfile({
    required String email,
    required String password,
  }) async {
    final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final idToken = await credential.user!.getIdToken();

    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/me/'),
      headers: {'Authorization': 'Bearer $idToken'},
    );

    if (response.statusCode != 200) {
      // Don't keep a Firebase session the backend refuses to recognize.
      await FirebaseAuth.instance.signOut();
      var message = 'Login rejected by server (${response.statusCode}).';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['detail'] is String) {
          message = body['detail'] as String;
        }
      } catch (_) {}
      throw BackendAuthException(message);
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> signOut() => FirebaseAuth.instance.signOut();
}
