import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/domain/repositories/auth_repository.dart';

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
    state = _next(isLoading: true);
    try {
      final profile = await ref.read(signInProvider)(
        email: email,
        password: password,
      );
      state = _next();
      return profile;
    } on AuthException catch (e) {
      state = _next(error: e.message);
    } catch (_) {
      state = _next(error: 'Could not sign in. Is the server running?');
    }
    return null;
  }

  Future<bool> sendResetEmail(String email) async {
    if (email.isEmpty) {
      state = _next(
        error: 'Enter your email above first, then tap "Forgot password?".',
      );
      return false;
    }
    state = _next(isSendingReset: true);
    try {
      await ref.read(sendPasswordResetProvider)(email: email);
      state = _next();
      return true;
    } on AuthException catch (e) {
      state = _next(error: e.message);
    } catch (_) {
      state = _next(error: 'Could not send reset email. Is the server running?');
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
  }) =>
      LoginState(
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
class PasswordResetController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Emails a password-reset link. Returns true on success so the View can
  /// confirm.
  Future<bool> send(String email) async {
    state = const AsyncLoading();
    try {
      await ref.read(sendPasswordResetProvider)(email: email);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}

final passwordResetControllerProvider =
    AsyncNotifierProvider.autoDispose<PasswordResetController, void>(
  PasswordResetController.new,
);
