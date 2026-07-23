import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/presentation/providers/auth_controllers.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';

/// UI-only view for changing the signed-in user's password. Validation and
/// the repository call live in [ChangePasswordController]; the text
/// controllers live here because they are View concerns.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key, this.email});

  /// The signed-in user's email, when the hosting screen knows it. Enables
  /// the "Forgot your current password?" reset-email fallback.
  final String? email;

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final ok = await ref.read(changePasswordControllerProvider.notifier).submit(
          currentPassword: _currentController.text,
          newPassword: _newController.text,
          confirmPassword: _confirmController.text,
        );
    if (!mounted || !ok) return;
    // The messenger lives above this route, so the confirmation survives
    // the pop back to the profile.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Password changed successfully.')),
    );
    Navigator.of(context).pop();
  }

  Future<void> _handleForgotPassword() async {
    final email = widget.email!;
    final sent =
        await ref.read(passwordResetControllerProvider.notifier).send(email);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sent
              ? 'Password reset email sent to $email.'
              : friendlyErrorMessage(
                  ref.read(passwordResetControllerProvider).error,
                  'Could not send the reset email. Please try again.',
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(changePasswordControllerProvider);
    final isSendingReset =
        ref.watch(passwordResetControllerProvider).isLoading;
    return Scaffold(
      appBar: AppBar(title: const Text('Change Password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Enter your current password, then choose a new one of at '
                  'least ${ChangePasswordController.minPasswordLength} '
                  'characters.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                _passwordField(
                  controller: _currentController,
                  label: 'Current password',
                  state: state,
                ),
                const SizedBox(height: 16),
                _passwordField(
                  controller: _newController,
                  label: 'New password',
                  state: state,
                ),
                const SizedBox(height: 16),
                _passwordField(
                  controller: _confirmController,
                  label: 'Confirm new password',
                  state: state,
                  isLast: true,
                ),
                if (state.error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    state.error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: state.isSaving ? null : _handleSubmit,
                  child: state.isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Change Password'),
                ),
                if (widget.email != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: isSendingReset ? null : _handleForgotPassword,
                    child: isSendingReset
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Forgot your current password?'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One shared visibility toggle: revealing while retyping is when users
  /// actually need to see what they typed, and one flag keeps the state
  /// transitions simple.
  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required ChangePasswordState state,
    bool isLast = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: !state.showPasswords,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
      onSubmitted:
          isLast ? (_) => state.isSaving ? null : _handleSubmit() : null,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(
            state.showPasswords ? Icons.visibility : Icons.visibility_off,
          ),
          onPressed: ref
              .read(changePasswordControllerProvider.notifier)
              .togglePasswordVisibility,
        ),
      ),
    );
  }
}
