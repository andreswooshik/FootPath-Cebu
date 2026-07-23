import 'package:footpath_cebu/domain/repositories/auth_repository.dart';

/// Use case: change the signed-in user's password, verifying the current one.
class ChangePassword {
  const ChangePassword(this._auth);

  final AuthRepository _auth;

  Future<void> call({
    required String currentPassword,
    required String newPassword,
  }) =>
      _auth.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
}
