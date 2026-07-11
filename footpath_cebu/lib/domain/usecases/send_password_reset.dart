import 'package:footpath_cebu/domain/repositories/auth_repository.dart';

/// Use case: send a password-reset email to the given address.
class SendPasswordReset {
  const SendPasswordReset(this._auth);

  final AuthRepository _auth;

  Future<void> call({required String email}) =>
      _auth.sendPasswordResetEmail(email: email);
}
