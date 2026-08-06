import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/domain/repositories/auth_repository.dart';

/// Mock implementation for UI development without Firebase.
class MockAuthRepository implements AuthRepository {
  UserProfile? _signedInProfile;

  /// Predefined test accounts for easy testing
  static const mockAccounts = {
    'player@example.com': 'demo123',
    'coach@example.com': 'demo123',
    'admin@example.com': 'demo123',
    'guardian@example.com': 'demo123',
    'john.doe@example.com': 'demo123',
    'maria.santos@example.com': 'demo123',
  };

  @override
  Future<UserProfile> signInAndFetchProfile({
    required String email,
    required String password,
  }) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    // Accept any email with password "demo123", OR use predefined accounts
    final isValidAccount =
        mockAccounts[email] == password || password == 'demo123';

    if (isValidAccount) {
      // Mirror the real /api/auth/me/ contract (upper-case role, name parts).
      final role = _getRoleFromEmail(email).toUpperCase();
      final profile = UserProfile(
        id: '${email.hashCode}'.replaceAll('-', ''),
        email: email,
        firstName: email.split('@')[0].replaceAll('.', ' ').titleCase,
        lastName: '',
        role: role,
        roleDisplay: role.titleCase,
      );
      _signedInProfile = profile;
      return profile;
    }

    // Simulate incorrect password
    throw AuthException('Incorrect email or password.');
  }

  @override
  Future<UserProfile?> restoreSession() async => _signedInProfile;

  String _getRoleFromEmail(String email) {
    if (email.contains('coach')) return 'coach';
    if (email.contains('admin')) return 'admin';
    if (email.contains('guardian') || email.contains('parent')) {
      return 'guardian';
    }
    return 'player';
  }

  @override
  Future<void> signOut() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _signedInProfile = null;
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    // Every mock account signs in with the shared demo password.
    if (currentPassword != 'demo123') {
      throw AuthException('Current password is incorrect.');
    }
  }

  @override
  Future<void> reauthenticate({
    required String email,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (email.trim().isEmpty || password != 'demo123') {
      throw AuthException('Guardian email or password is incorrect.');
    }
  }
}

extension on String {
  String get titleCase {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1).toLowerCase();
  }
}
