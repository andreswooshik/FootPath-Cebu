import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/player_privacy_pin_repository.dart';
import 'package:footpath_cebu/presentation/providers/player_privacy_pin_providers.dart';

class PlayerPrivacyPinScreen extends ConsumerStatefulWidget {
  const PlayerPrivacyPinScreen({super.key, required this.player});

  final Player player;

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
      await ref.read(setPlayerPrivacyPinProvider)(
        widget.player.id,
        pin: pin,
        currentPin: hasPin ? _currentController.text : null,
      );
      ref.invalidate(playerPrivacyPinStatusProvider(widget.player.id));
      ref
          .read(privacyUnlockedPlayersProvider.notifier)
          .unlock(widget.player.id);
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
        data: (pinStatus) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.lock_outline, size: 56),
            const SizedBox(height: 16),
            Text(
              pinStatus.hasPin
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
        ),
      ),
    );
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
