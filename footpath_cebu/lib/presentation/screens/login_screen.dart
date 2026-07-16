import 'dart:async';

import 'package:flutter/material.dart';

import 'package:footpath_cebu/core/di/service_locator.dart';
import 'package:footpath_cebu/presentation/screens/home_screen.dart';
import 'package:footpath_cebu/presentation/viewmodels/login_viewmodel.dart';

/// UI-only view for login. All business logic is in LoginViewModel.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final LoginViewModel _viewModel = LoginViewModel(
    ServiceLocator.signIn,
    ServiceLocator.sendPasswordReset,
  );

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    final profile = await _viewModel.signIn();
    if (!mounted) return;
    if (profile != null) {
      // Register this device for push notifications (best-effort, fire and
      // forget — never blocks navigation or fails the login).
      unawaited(ServiceLocator.registerDevice());
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeScreen(profile: profile)),
      );
    }
  }

  Future<void> _handleForgotPassword() async {
    final sent = await _viewModel.sendResetEmail();
    if (!mounted) return;
    if (sent) {
      final email = _viewModel.emailController.text.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset email sent to $email.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.sports_soccer,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'FootPath Cebu',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _viewModel.emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _viewModel.passwordController,
                      obscureText: !_viewModel.showPassword,
                      onSubmitted: (_) =>
                          _viewModel.isLoading ? null : _handleSignIn(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _viewModel.showPassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: _viewModel.togglePasswordVisibility,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _viewModel.isSendingReset
                            ? null
                            : _handleForgotPassword,
                        child: _viewModel.isSendingReset
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Forgot password?'),
                      ),
                    ),
                    if (_viewModel.error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _viewModel.error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed:
                          _viewModel.isLoading ? null : _handleSignIn,
                      child: _viewModel.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Sign In'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Accounts are issued by the academy administrator.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
