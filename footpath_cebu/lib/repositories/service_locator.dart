import 'auth_repository.dart';
import 'firebase_auth_repository.dart';
import 'mock_auth_repository.dart';

/// Simple service locator for dependency injection.
class ServiceLocator {
  static late AuthRepository _authRepository;

  /// Initialize with mock repository for UI development.
  static void initMock() {
    _authRepository = MockAuthRepository();
  }

  /// Initialize with Firebase repository for production.
  static void initFirebase() {
    _authRepository = FirebaseAuthRepository();
  }

  /// Get the current auth repository instance.
  static AuthRepository get authRepository => _authRepository;
}
