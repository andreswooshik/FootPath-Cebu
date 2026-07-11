import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/user_profile.dart';
import 'auth_repository.dart';

/// Firebase implementation of [AuthRepository].
///
/// Signs in with Firebase, verifies the ID token against the Django backend,
/// and returns a typed [UserProfile]. All Firebase-specific errors are
/// translated to [AuthException] here so the presentation layer never imports
/// `firebase_auth`.
class FirebaseAuthRepository implements AuthRepository {
  @override
  Future<UserProfile> signInAndFetchProfile({
    required String email,
    required String password,
  }) async {
    final UserCredential credential;
    try {
      credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(_friendlyAuthMessage(e));
    }

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
      throw AuthException(message);
    }

    return UserProfile.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  @override
  Future<void> signOut() => FirebaseAuth.instance.signOut();

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_friendlyAuthMessage(e));
    }
  }

  /// Maps Firebase error codes to user-facing copy. Lives in the data layer so
  /// the ViewModel depends only on [AuthException].
  String _friendlyAuthMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Incorrect email or password.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      default:
        return 'Sign-in failed (${e.code}).';
    }
  }
}
