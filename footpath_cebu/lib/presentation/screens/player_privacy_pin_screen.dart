import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/auth_repository.dart';
import 'package:footpath_cebu/domain/repositories/player_privacy_pin_repository.dart';
import 'package:footpath_cebu/presentation/providers/player_privacy_pin_providers.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';

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
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save(bool hasPin) async {
    final pin = _pinController.text;
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      setState(() => _error = 'PIN must contain 4 to 6 digits.');
      return;
    }
    if (pin != _confirmController.text) {
      setState(() => _error = 'PINs do not match.');
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

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(playerPrivacyPinStatusProvider(widget.player.id));
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy PIN')),
      body: status.when(
        loading: () => const DashboardLoadingState(compact: true),
        error: (error, _) => Center(child: Text(error.toString())),
        data: (pinStatus) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.lock_outline, size: 56),
            const SizedBox(height: 16),
            Text(
              pinStatus.hasPin && widget.isGuardian
                  ? 'Manage ${widget.player.name}’s PIN'
                  : pinStatus.hasPin
                  ? 'Change your player PIN'
                  : 'Create your player PIN',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Use 4 to 6 digits. This protects your player profile on shared household devices.',
              textAlign: TextAlign.center,
            ),
            if (pinStatus.hasPin && widget.isGuardian) ...[
              const SizedBox(height: 24),
              const Text(
                'The player already has a PIN. Reset it before creating a new one.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: _saving ? null : _resetAsGuardian,
                child: const Text('Reset player PIN'),
              ),
            ] else ...[
              if (pinStatus.hasPin) ...[
                const SizedBox(height: 24),
                _pinField(_currentController, 'Current PIN'),
              ],
              const SizedBox(height: 12),
              _pinField(_pinController, 'New PIN'),
              const SizedBox(height: 12),
              _pinField(_confirmController, 'Confirm PIN'),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Colors.red.shade700)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : () => _save(pinStatus.hasPin),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(pinStatus.hasPin ? 'Change PIN' : 'Create PIN'),
              ),
            ],
          ],
        ),
      ),
    ).animateScreenEntrance();
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
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on PlayerPrivacyPinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _pinField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 6,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        counterText: '',
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
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _continue() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter the guardian email and password.');
      return;
    }
    Navigator.of(context).pop(_GuardianCredentials(email, password));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Verify guardian account'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'For security, verify the guardian account before resetting this player PIN.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Guardian email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              onSubmitted: (_) => _continue(),
              decoration: const InputDecoration(
                labelText: 'Guardian password',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _continue, child: const Text('Verify')),
      ],
    );
  }
}
