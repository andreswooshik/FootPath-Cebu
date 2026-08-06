import 'package:footpath_cebu/domain/repositories/auth_repository.dart';

/// Use case: prove the signed-in user's credentials before a sensitive action.
class Reauthenticate {
  const Reauthenticate(this._auth);

  final AuthRepository _auth;

  Future<void> call({required String email, required String password}) =>
      _auth.reauthenticate(email: email, password: password);
}
