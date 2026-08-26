import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/auth_repository.dart';
import 'package:footpath_cebu/domain/repositories/player_privacy_pin_repository.dart';
import 'package:footpath_cebu/presentation/providers/player_privacy_pin_providers.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/privacy_pin_ui.dart';

class PlayerPrivacyPinScreen extends ConsumerStatefulWidget {
  const PlayerPrivacyPinScreen({
    super.key,
    required this.player,
    this.isGuardian = false,
  });

  final Player player;
  final bool isGuardian;

  @override
  ConsumerState<PlayerPrivacyPinScreen> createState() =>
      _PlayerPrivacyPinScreenState();
}

class _PlayerPrivacyPinScreenState
    extends ConsumerState<PlayerPrivacyPinScreen> {
  final _currentController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  final _currentFocus = FocusNode();
  final _pinFocus = FocusNode();
  final _confirmFocus = FocusNode();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _pinController.dispose();
    _confirmController.dispose();
    _currentFocus.dispose();
    _pinFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _save(bool hasPin) async {
    if (_saving) return;
    if (hasPin && !RegExp(r'^\d{4,6}$').hasMatch(_currentController.text)) {
      setState(() => _error = 'Enter your current 4 to 6 digit PIN.');
      _currentFocus.requestFocus();
      return;
    }

    final pin = _pinController.text;
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      setState(() => _error = 'New PIN must contain 4 to 6 digits.');
      _pinFocus.requestFocus();
      return;
    }
    if (pin != _confirmController.text) {
      setState(() => _error = 'PINs do not match. Try entering them again.');
      _confirmFocus.requestFocus();
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await ref.read(setPlayerPrivacyPinProvider)(
        widget.player.id,
        pin: pin,
        currentPin: hasPin ? _currentController.text : null,
      );
      ref.invalidate(playerPrivacyPinStatusProvider(widget.player.id));
      ref
          .read(privacyUnlockedPlayersProvider.notifier)
          .unlock(widget.player.id, result.unlockToken ?? '');
      if (mounted) Navigator.of(context).pop();
    } on PlayerPrivacyPinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(playerPrivacyPinStatusProvider(widget.player.id));
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy PIN')),
      body: status.when(
        loading: () => const DashboardLoadingState(compact: true),
        error: (error, _) => _StatusError(
          onRetry: () =>
              ref.invalidate(playerPrivacyPinStatusProvider(widget.player.id)),
        ),
        data: (pinStatus) => _buildContent(pinStatus.hasPin),
      ),
    ).animateScreenEntrance();
  }

  Widget _buildContent(bool hasPin) {
    if (hasPin && widget.isGuardian) {
      return PrivacyPinPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PrivacyPinHeader(
              title: 'Manage ${widget.player.name}’s PIN',
              description:
                  'A privacy PIN is active for this player’s private profile.',
              icon: Icons.verified_user_outlined,
              badgeLabel: 'PIN ACTIVE',
            ),
            const SizedBox(height: 24),
            _ResetInformation(playerName: widget.player.name),
            if (_error != null) ...[
              const SizedBox(height: 14),
              PrivacyPinErrorBanner(message: _error!),
            ],
            const SizedBox(height: 22),
            PrivacyPinPrimaryButton(
              label: 'Verify and reset PIN',
              onPressed: _resetAsGuardian,
              busy: _saving,
              icon: Icons.lock_reset_outlined,
            ),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    final title = hasPin ? 'Change your privacy PIN' : 'Create a privacy PIN';
    final description = hasPin
        ? 'Update the PIN that protects ${widget.player.name}’s private profile.'
        : 'Add a secure household PIN for ${widget.player.name}’s private profile.';

    return PrivacyPinPanel(
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PrivacyPinHeader(
              title: title,
              description: description,
              icon: hasPin ? Icons.lock_reset_outlined : Icons.shield_outlined,
              badgeLabel: hasPin ? 'UPDATE SECURITY' : 'PROFILE SECURITY',
            ),
            const SizedBox(height: 24),
            PrivacyPinGuidance(isChange: hasPin),
            const SizedBox(height: 20),
            Text(
              hasPin ? 'Confirm and update' : 'Choose your PIN',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              hasPin
                  ? 'Enter your current PIN, then choose a new one.'
                  : 'Enter it twice to make sure it is correct.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            if (hasPin) ...[
              PrivacyPinField(
                controller: _currentController,
                focusNode: _currentFocus,
                label: 'Current privacy PIN',
                enabled: !_saving,
                autofocus: true,
                onChanged: (_) => _clearError(),
                onSubmitted: (_) => _pinFocus.requestFocus(),
              ),
              const SizedBox(height: 14),
            ],
            PrivacyPinField(
              controller: _pinController,
              focusNode: _pinFocus,
              label: 'New privacy PIN',
              enabled: !_saving,
              autofocus: !hasPin,
              onChanged: (_) => _clearError(),
              onSubmitted: (_) => _confirmFocus.requestFocus(),
            ),
            const SizedBox(height: 14),
            PrivacyPinField(
              controller: _confirmController,
              focusNode: _confirmFocus,
              label: 'Confirm privacy PIN',
              enabled: !_saving,
              textInputAction: TextInputAction.done,
              onChanged: (_) => _clearError(),
              onSubmitted: (_) => _save(hasPin),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              PrivacyPinErrorBanner(message: _error!),
            ],
            const SizedBox(height: 22),
            PrivacyPinPrimaryButton(
              label: hasPin ? 'Save new PIN' : 'Create privacy PIN',
              onPressed: () => _save(hasPin),
              busy: _saving,
              icon: hasPin ? Icons.check_rounded : Icons.lock_rounded,
            ),
            const SizedBox(height: 14),
            Text(
              'Your PIN is stored securely and is never displayed in your profile.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resetAsGuardian() async {
    final credentials = await showDialog<_GuardianCredentials>(
      context: context,
      builder: (_) => const _GuardianReauthenticationDialog(),
    );
    if (credentials == null || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // The guardian password is used only to re-authenticate with Firebase;
      // it is never sent to Django or stored in this screen.
      await ref.read(reauthenticateProvider)(
        email: credentials.email,
        password: credentials.password,
      );
      await ref.read(resetPlayerPrivacyPinProvider)(widget.player.id);
      ref.invalidate(playerPrivacyPinStatusProvider(widget.player.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Privacy PIN reset successfully.')),
        );
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on PlayerPrivacyPinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _StatusError extends StatelessWidget {
  const _StatusError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 44),
            const SizedBox(height: 12),
            Text(
              'Could not check PIN status',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResetInformation extends StatelessWidget {
  const _ResetInformation({required this.playerName});

  final String playerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.admin_panel_settings_outlined, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Guardian verification required',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'For security, verify your guardian account before removing $playerName’s current PIN. You can create a new PIN after the reset.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuardianCredentials {
  const _GuardianCredentials(this.email, this.password);

  final String email;
  final String password;
}

class _GuardianReauthenticationDialog extends StatefulWidget {
  const _GuardianReauthenticationDialog();

  @override
  State<_GuardianReauthenticationDialog> createState() =>
      _GuardianReauthenticationDialogState();
}

class _GuardianReauthenticationDialogState
    extends State<_GuardianReauthenticationDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _continue() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your guardian email and password.');
      return;
    }
    Navigator.of(context).pop(_GuardianCredentials(email, password));
  }

  void _clearError(String _) {
    if (_error != null) setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      icon: const Icon(Icons.verified_user_outlined, size: 34),
      title: const Text('Verify guardian account'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Confirm your identity before resetting the player’s privacy PIN.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofocus: true,
                autofillHints: const [AutofillHints.email],
                onChanged: _clearError,
                onSubmitted: (_) => _passwordFocus.requestFocus(),
                decoration: InputDecoration(
                  labelText: 'Guardian email',
                  filled: true,
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _passwordController,
                focusNode: _passwordFocus,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onChanged: _clearError,
                onSubmitted: (_) => _continue(),
                decoration: InputDecoration(
                  labelText: 'Guardian password',
                  filled: true,
                  prefixIcon: const Icon(Icons.password_outlined),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Show password'
                        : 'Hide password',
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                PrivacyPinErrorBanner(message: _error!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _continue,
          icon: const Icon(Icons.verified_outlined),
          label: const Text('Verify'),
        ),
      ],
    );
  }
}
