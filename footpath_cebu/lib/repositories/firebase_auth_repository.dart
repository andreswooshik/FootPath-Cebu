import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'auth_repository.dart';

/// Firebase implementation of AuthRepository.
/// Signs in with Firebase and verifies against Django backend.
class FirebaseAuthRepository implements AuthRepository {
  @override
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
      await FirebaseAuth.instance.signOut();
      var message = 'Login rejected by server (${response.statusCode}).';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['detail'] is String) {
          message = body['detail'] as String;
        }
      } catch (_) {}
      throw AuthException(message);
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  @override
  Future<void> signOut() => FirebaseAuth.instance.signOut();

  @override
  Future<void> sendPasswordResetEmail({required String email}) {
    return FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  }
}
