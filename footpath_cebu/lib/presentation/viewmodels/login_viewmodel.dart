import 'package:flutter/material.dart';

import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/domain/repositories/auth_repository.dart';
import 'package:footpath_cebu/domain/usecases/send_password_reset.dart';
import 'package:footpath_cebu/domain/usecases/sign_in.dart';

/// Handles login and password reset business logic.
///
/// Manages authentication state, error handling, and user input without
/// any UI dependencies. The View (LoginScreen) only displays state and
/// calls these methods.
class LoginViewModel extends ChangeNotifier {
  LoginViewModel(this._signIn, this._sendPasswordReset);

  final SignIn _signIn;
  final SendPasswordReset _sendPasswordReset;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool _loading = false;
  bool _sendingReset = false;
  bool _showPassword = false;
  String? _error;

  bool get isLoading => _loading;
  bool get isSendingReset => _sendingReset;
  bool get showPassword => _showPassword;
  String? get error => _error;

  void togglePasswordVisibility() {
    _showPassword = !_showPassword;
    notifyListeners();
  }

  Future<UserProfile?> signIn() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final profile = await _signIn(
        email: emailController.text.trim(),
        password: passwordController.text,
      );
      _loading = false;
      notifyListeners();
      return profile;
    } on AuthException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Could not sign in. Is the server running?';
    } finally {
      _loading = false;
      notifyListeners();
    }
    return null;
  }

  Future<bool> sendResetEmail() async {
    final email = emailController.text.trim();
    if (email.isEmpty) {
      _error = 'Enter your email above first, then tap "Forgot password?".';
      notifyListeners();
      return false;
    }

    _sendingReset = true;
    _error = null;
    notifyListeners();

    try {
      await _sendPasswordReset(email: email);
      _sendingReset = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Could not send reset email. Is the server running?';
    } finally {
      _sendingReset = false;
      notifyListeners();
    }
    return false;
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}
