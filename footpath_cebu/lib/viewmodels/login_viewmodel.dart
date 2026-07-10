import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../repositories/auth_repository.dart';

/// Handles login and password reset business logic.
///
/// Manages authentication state, error handling, and user input without
/// any UI dependencies. The View (LoginScreen) only displays state and
/// calls these methods.
class LoginViewModel extends ChangeNotifier {
  LoginViewModel(this._authRepository);

  final AuthRepository _authRepository;

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

  Future<Map<String, dynamic>?> signIn() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final profile = await _authRepository.signInAndFetchProfile(
        email: emailController.text.trim(),
        password: passwordController.text,
      );
      _loading = false;
      notifyListeners();
      return profile;
    } on FirebaseAuthException catch (e) {
      _error = _friendlyAuthMessage(e);
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
      await _authRepository.sendPasswordResetEmail(email: email);
      _sendingReset = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _friendlyAuthMessage(e);
    } catch (e) {
      _error = 'Could not send reset email. Is the server running?';
    } finally {
      _sendingReset = false;
      notifyListeners();
    }
    return false;
  }

  String _friendlyAuthMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Incorrect email or password.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      default:
        return 'Sign-in failed (${e.code}).';
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}
