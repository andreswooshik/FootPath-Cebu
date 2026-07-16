import 'package:footpath_cebu/domain/entities/user_profile.dart';

/// Abstract interface for authentication operations.
abstract class AuthRepository {
  /// Signs in with email and password, returning the typed user profile.
  ///
  /// Implementations translate provider-specific failures (e.g. Firebase's
  /// [FirebaseAuthException]) into [AuthException] so callers — the
  /// presentation controllers — never depend on the auth provider.
  Future<UserProfile> signInAndFetchProfile({
    required String email,
    required String password,
  });

  /// Signs out the current user.
  Future<void> signOut();

  /// Sends a password reset email to the given address.
  Future<void> sendPasswordResetEmail({required String email});
}

/// Thrown when sign-in fails.
class AuthException implements Exception {
  AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
