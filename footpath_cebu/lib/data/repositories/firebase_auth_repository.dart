import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:footpath_cebu/data/local/api_get_cache.dart';
import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/domain/repositories/auth_repository.dart';

/// Typed `/api/auth/me/` access through the same authenticated timeout and
/// error boundary used by the other live REST repositories.
class FirebaseProfileApi {
  FirebaseProfileApi({AuthenticatedApiClient? api})
    : _api = api ?? AuthenticatedApiClient.shared;

  final AuthenticatedApiClient _api;

  Future<UserProfile> fetchCurrentProfile() async {
    // Authentication bootstrap must prove the backend recognizes the current
    // identity. It must never succeed from an offline cached profile.
    final response = await _api.get('/api/auth/me/', cache: false);
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException();
      return UserProfile.fromJson(Map<String, dynamic>.from(decoded));
    } on FormatException {
      throw const ApiDecodeException(
        'The server returned an invalid account profile.',
      );
    } on TypeError {
      throw const ApiDecodeException(
        'The server returned an invalid account profile.',
      );
    }
  }
}

/// Firebase implementation of [AuthRepository].
///
/// Signs in with Firebase, verifies the ID token against the Django backend,
/// and returns a typed [UserProfile]. All Firebase-specific errors are
/// translated to [AuthException] here so the presentation layer never imports
/// `firebase_auth`.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    ApiGetCache? apiCache,
    FirebaseProfileApi? profileApi,
  }) : _apiCache = apiCache ?? ApiGetCache.shared,
       _profileApi = profileApi ?? FirebaseProfileApi();

  final ApiGetCache _apiCache;
  final FirebaseProfileApi _profileApi;

  @override
  Future<UserProfile?> restoreSession() async {
    // `currentUser` may still be null during the first frame while Firebase
    // restores its local credentials. Wait for the initial auth-state event
    // so a valid saved session is not mistaken for a signed-out user.
    final user = await FirebaseAuth.instance.authStateChanges().first;
    if (user == null) return null;

    try {
      return await _profileApi.fetchCurrentProfile();
    } on ApiAuthenticationException {
      await _signOutAndClearCache();
      return null;
    } on ApiHttpException catch (error) {
      // Only an explicit authentication/authorization rejection invalidates
      // the local Firebase session. Preserve it during outages so closing and
      // reopening the app does not force an unnecessary sign-in.
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _signOutAndClearCache();
      }
      throw AuthException(error.message);
    } on ApiException catch (error) {
      throw AuthException(error.message);
    }
  }

  @override
  Future<UserProfile> signInAndFetchProfile({
    required String email,
    required String password,
  }) async {
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(_friendlyAuthMessage(e));
    }

    try {
      return await _profileApi.fetchCurrentProfile();
    } on ApiAuthenticationException catch (error) {
      await _signOutAndClearCache();
      throw AuthException(error.message);
    } on ApiHttpException catch (error) {
      // Don't keep a Firebase session the backend refuses to recognize.
      await _signOutAndClearCache();
      throw AuthException(error.message);
    } on ApiException catch (error) {
      throw AuthException(error.message);
    }
  }

  @override
  Future<void> signOut() => _signOutAndClearCache();

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

  @override
  Future<void> reauthenticate({
    required String email,
    required String password,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      throw AuthException('Your session has expired. Please sign in again.');
    }
    if (user.email!.trim().toLowerCase() != email.trim().toLowerCase()) {
      throw AuthException(
        'Enter the email for the signed-in guardian account.',
      );
    }
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: user.email!, password: password),
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-credential' || e.code == 'wrong-password') {
        throw AuthException('Guardian email or password is incorrect.');
      }
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

  Future<void> _signOutAndClearCache() async {
    final ownerUid = FirebaseAuth.instance.currentUser?.uid;
    await FirebaseAuth.instance.signOut();
    if (ownerUid == null || ownerUid.isEmpty) return;
    try {
      await _apiCache.clearOwner(ownerUid);
    } catch (_) {
      // SQLite is unavailable in some web builds. Those builds cannot have
      // written this cache, and a successful Firebase sign-out must still
      // complete.
    }
  }
}
