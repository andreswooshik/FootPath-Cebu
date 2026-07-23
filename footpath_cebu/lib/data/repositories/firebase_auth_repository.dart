import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:footpath_cebu/core/config/api_config.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/domain/repositories/auth_repository.dart';
import 'package:http/http.dart' as http;

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

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      throw AuthException('Your session has expired. Please sign in again.');
    }

    // Firebase requires a recent sign-in before sensitive changes; proving
    // the current password satisfies that and stops someone with a borrowed
    // unlocked phone from silently taking over the account.
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(
          email: user.email!,
          password: currentPassword,
        ),
      );
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        // The generic mapping says "Incorrect email or password", which is
        // misleading here — only the current password can be wrong.
        case 'invalid-credential':
        case 'wrong-password':
          throw AuthException('Current password is incorrect.');
        default:
          throw AuthException(_friendlyAuthMessage(e));
      }
    }

    try {
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_friendlyAuthMessage(e));
    }
  }

  /// Maps Firebase error codes to user-facing copy. Lives in the data layer so
  /// the presentation layer depends only on [AuthException].
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
      case 'weak-password':
        return 'New password is too weak. Use at least 8 characters.';
      case 'requires-recent-login':
        return 'For security, please sign out, sign in again, and retry.';
      default:
        return 'Sign-in failed (${e.code}).';
    }
  }
}
