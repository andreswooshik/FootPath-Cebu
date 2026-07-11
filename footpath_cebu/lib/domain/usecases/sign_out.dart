import 'package:footpath_cebu/domain/repositories/auth_repository.dart';

/// Use case: sign the current user out.
class SignOut {
  const SignOut(this._auth);

  final AuthRepository _auth;

  Future<void> call() => _auth.signOut();
}
