import 'package:footpath_cebu/domain/repositories/auth_repository.dart';

/// Use case: sign the current user out.
class SignOut {
  const SignOut(this._auth, {this.onSignedOut});

  final AuthRepository _auth;
  final void Function()? onSignedOut;

  Future<void> call() async {
    await _auth.signOut();
    onSignedOut?.call();
  }
}
