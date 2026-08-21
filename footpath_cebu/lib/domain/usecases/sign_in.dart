import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/domain/repositories/auth_repository.dart';

/// Use case: authenticate the user and return their profile.
///
/// A single business operation, depending only on the [AuthRepository]
/// abstraction — the domain layer points at nothing outward (Dependency Rule).
class SignIn {
  const SignIn(this._auth);

  final AuthRepository _auth;

  Future<UserProfile> call({required String email, required String password}) {
    return _auth.signInAndFetchProfile(email: email, password: password);
  }
}
