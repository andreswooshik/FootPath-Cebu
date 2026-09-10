import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/domain/repositories/auth_repository.dart';
import 'package:footpath_cebu/presentation/providers/mutation_controller.dart';

/// What the login form is doing right now. Immutable; every transition
/// replaces the whole state (and clears the error unless one is set).
class LoginState {
  const LoginState({
    this.isLoading = false,
    this.isSendingReset = false,
    this.showPassword = false,
    this.error,
  });

  final bool isLoading;
  final bool isSendingReset;
  final bool showPassword;
  final String? error;
}

/// Handles login and password-reset business logic for the login screen.
/// The View only renders [LoginState] and forwards user intent here.
class LoginController extends Notifier<LoginState> {
  @override
  LoginState build() => const LoginState();

  void togglePasswordVisibility() =>
      state = _next(showPassword: !state.showPassword, error: state.error);

  Future<UserProfile?> signIn({
    required String email,
    required String password,
  }) async {
    if (!ref.mounted || state.isLoading || state.isSendingReset) return null;
    state = _next(isLoading: true);
    try {
      final profile = await ref.read(signInProvider)(
        email: email,
        password: password,
      );
      if (!ref.mounted) return null;
      state = _next();
      return profile;
    } on AuthException catch (e) {
      if (ref.mounted) state = _next(error: e.message);
    } catch (_) {
      if (ref.mounted) {
        state = _next(error: 'Could not sign in. Please try again.');
      }
    }
    return null;
  }

  Future<bool> sendResetEmail(String email) async {
    if (!ref.mounted || state.isLoading || state.isSendingReset) return false;
    if (email.isEmpty) {
      state = _next(
        error: 'Enter your email above first, then tap "Forgot password?".',
      );
      return false;
    }
    state = _next(isSendingReset: true);
    try {
      await ref.read(sendPasswordResetProvider)(email: email);
      if (!ref.mounted) return false;
      state = _next();
      return true;
    } on AuthException catch (e) {
      if (ref.mounted) state = _next(error: e.message);
    } catch (_) {
      if (ref.mounted) {
        state = _next(error: 'Could not send reset email. Please try again.');
      }
    }
    return false;
  }

  /// A transition: busy flags reset unless passed, the error clears unless
  /// passed, and the password visibility toggle always survives.
  LoginState _next({
    bool isLoading = false,
    bool isSendingReset = false,
    bool? showPassword,
    String? error,
  }) => LoginState(
    isLoading: isLoading,
    isSendingReset: isSendingReset,
    showPassword: showPassword ?? state.showPassword,
    error: error,
  );
}

final loginControllerProvider =
    NotifierProvider.autoDispose<LoginController, LoginState>(
      LoginController.new,
    );

/// Drives the Coach profile's "Change password" action: sends a reset link
/// and exposes the in-flight/error state as an [AsyncValue].
class PasswordResetController extends MutationController {
  /// Emails a password-reset link. Returns true on success so the View can
  /// confirm.
  Future<bool> send(String email) async {
    return await runMutation(() async {
          await ref.read(sendPasswordResetProvider)(email: email);
          return true;
        }) ??
        false;
  }
}

final passwordResetControllerProvider =
    AsyncNotifierProvider.autoDispose<PasswordResetController, void>(
      PasswordResetController.new,
    );

/// What the change-password form is doing right now. Immutable, same
/// transition discipline as [LoginState].
class ChangePasswordState {
  const ChangePasswordState({
    this.isSaving = false,
    this.showPasswords = false,
    this.error,
  });

  final bool isSaving;
  final bool showPasswords;
  final String? error;
}

/// Validates and submits a password change. The View only renders
/// [ChangePasswordState] and forwards the three field values here.
class ChangePasswordController extends Notifier<ChangePasswordState> {
  /// Stricter than Firebase's 6-char minimum; admins issue 12-char temp
  /// passwords, so users should not downgrade to something trivial.
  static const minPasswordLength = 8;

  @override
  ChangePasswordState build() => const ChangePasswordState();

  void togglePasswordVisibility() =>
      state = _next(showPasswords: !state.showPasswords, error: state.error);

  /// Returns true when the password was changed, so the View can confirm
  /// and close.
  Future<bool> submit({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    if (!ref.mounted || state.isSaving) return false;
    final validationError = _validate(
      currentPassword,
      newPassword,
      confirmPassword,
    );
    if (validationError != null) {
      state = _next(error: validationError);
      return false;
    }

    state = _next(isSaving: true);
    try {
      await ref.read(changePasswordProvider)(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      if (!ref.mounted) return false;
      state = _next();
      return true;
    } on AuthException catch (e) {
      if (ref.mounted) state = _next(error: e.message);
    } catch (_) {
      if (ref.mounted) {
        state = _next(error: 'Could not change password. Please try again.');
      }
    }
    return false;
  }

  /// The form rules, kept here (not in the View) so they are unit-testable.
  String? _validate(String current, String next, String confirm) {
    if (current.isEmpty) return 'Enter your current password.';
    if (next.length < minPasswordLength) {
      return 'New password must be at least $minPasswordLength characters.';
    }
    if (next == current) {
      return 'New password must be different from your current password.';
    }
    if (next != confirm) return 'New passwords do not match.';
    return null;
  }

  ChangePasswordState _next({
    bool isSaving = false,
    bool? showPasswords,
    String? error,
  }) => ChangePasswordState(
    isSaving: isSaving,
    showPasswords: showPasswords ?? state.showPasswords,
    error: error,
  );
}

final changePasswordControllerProvider =
    NotifierProvider.autoDispose<ChangePasswordController, ChangePasswordState>(
      ChangePasswordController.new,
    );
