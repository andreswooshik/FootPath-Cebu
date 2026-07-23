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

  /// Changes the signed-in user's password after proving they know the
  /// current one. Throws [AuthException] when the current password is wrong
  /// or the new one is rejected by the provider.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });
}

/// Thrown when sign-in fails.
class AuthException implements Exception {
  AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
