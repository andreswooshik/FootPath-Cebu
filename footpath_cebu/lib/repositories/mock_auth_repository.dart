import 'auth_repository.dart';

/// Mock implementation for UI development without Firebase.
class MockAuthRepository implements AuthRepository {
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
  Future<Map<String, dynamic>> signInAndFetchProfile({
    required String email,
    required String password,
  }) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    // Accept any email with password "demo123", OR use predefined accounts
    final isValidAccount = mockAccounts[email] == password || password == 'demo123';

    if (isValidAccount) {
      return {
        'id': '${email.hashCode}'.replaceAll('-', ''),
        'email': email,
        'name': email.split('@')[0].replaceAll('.', ' ').titleCase,
        'role': _getRoleFromEmail(email),
        'avatar': null,
        'created_at': '2024-01-01T00:00:00Z',
      };
    }

    // Simulate incorrect password
    throw AuthException('Incorrect email or password.');
  }

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
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    await Future.delayed(const Duration(milliseconds: 500));
  }
}

extension on String {
  String get titleCase {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1).toLowerCase();
  }
}
