/// Abstract interface for authentication operations.
abstract class AuthRepository {
  /// Signs in with email and password, returns user profile.
  /// Profile includes: email, role, name, id, etc.
  Future<Map<String, dynamic>> signInAndFetchProfile({
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
