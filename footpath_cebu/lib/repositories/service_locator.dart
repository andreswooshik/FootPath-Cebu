import 'api_player_repository.dart';
import 'auth_repository.dart';
import 'firebase_auth_repository.dart';
import 'mock_auth_repository.dart';
import 'mock_player_repository.dart';
import 'player_repository.dart';

/// Simple service locator for dependency injection.
class ServiceLocator {
  static late AuthRepository _authRepository;
  static late PlayerRepository _playerRepository;

  /// Initialize with mock repositories for UI development.
  static void initMock() {
    _authRepository = MockAuthRepository();
    _playerRepository = MockPlayerRepository();
  }

  /// Initialize with live (Firebase/Django) repositories for production.
  static void initFirebase() {
    _authRepository = FirebaseAuthRepository();
    _playerRepository = ApiPlayerRepository();
  }

  /// Get the current auth repository instance.
  static AuthRepository get authRepository => _authRepository;

  /// Get the current player repository instance.
  static PlayerRepository get playerRepository => _playerRepository;
}
