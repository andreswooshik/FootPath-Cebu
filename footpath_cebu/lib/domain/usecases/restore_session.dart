import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/domain/repositories/auth_repository.dart';

/// Use case: restore the provider's persisted session on app startup.
class RestoreSession {
  const RestoreSession(this._auth);

  final AuthRepository _auth;

  Future<UserProfile?> call() => _auth.restoreSession();
}
