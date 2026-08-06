import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/player_privacy_pin_repository.dart';
import 'package:footpath_cebu/presentation/providers/player_privacy_pin_providers.dart';
import 'package:footpath_cebu/presentation/screens/player_privacy_pin_screen.dart';

/// Whether child-scoped navigation should be available right now.
///
/// Loading and error states stay hidden so a user cannot navigate around a
/// privacy prompt while the PIN status is being checked.
bool isPlayerPrivacyGateActive(
  WidgetRef ref,
  String playerId, {
  bool requirePinSetup = false,
}) {
  if (ref.watch(privacyUnlockedPlayersProvider).contains(playerId)) {
    return false;
  }
  final status = ref.watch(playerPrivacyPinStatusProvider(playerId));
  return status.when(
    loading: () => true,
    error: (error, stackTrace) => true,
    data: (pinStatus) => pinStatus.hasPin || requirePinSetup,
  );
}

/// Protects child-scoped content after a player has enabled a household PIN.
/// The unlocked state is session-only and contains no secret material.
class PlayerPrivacyGate extends ConsumerStatefulWidget {
  const PlayerPrivacyGate({
    super.key,
    required this.player,
    required this.child,
    this.isGuardian = false,
    this.requirePinSetup = false,
  });

  final Player player;
  final Widget child;
  final bool isGuardian;
  final bool requirePinSetup;

  @override
  ConsumerState<PlayerPrivacyGate> createState() => _PlayerPrivacyGateState();
}

class _PlayerPrivacyGateState extends ConsumerState<PlayerPrivacyGate> {
  final _pinController = TextEditingController();
  final _setupPinController = TextEditingController();
  final _setupConfirmController = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void didUpdateWidget(covariant PlayerPrivacyGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player.id == widget.player.id) return;

    // The gate state is reused when the guardian changes the selected player.
    // Never carry a PIN, setup PIN, confirmation, or error into another
    // profile.
    _pinController.clear();
    _setupPinController.clear();
    _setupConfirmController.clear();
    _error = null;
    _busy = false;
  }

  @override
  void dispose() {
    _pinController.dispose();
    _setupPinController.dispose();
    _setupConfirmController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final pin = _pinController.text;
    if (pin.length < 4) {
      setState(() => _error = 'Enter your 4 to 6 digit PIN.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await ref.read(verifyPlayerPrivacyPinProvider)(
        widget.player.id,
        pin,
      );
      ref
          .read(privacyUnlockedPlayersProvider.notifier)
          .unlock(widget.player.id, token);
    } on PlayerPrivacyPinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createPin() async {
    final pin = _setupPinController.text;
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      setState(() => _error = 'PIN must contain 4 to 6 digits.');
      return;
    }
    if (pin != _setupConfirmController.text) {
      setState(() => _error = 'PINs do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(setPlayerPrivacyPinProvider)(
        widget.player.id,
        pin: pin,
      );
      final token = result.unlockToken;
      if (token == null || token.isEmpty) {
        throw const PlayerPrivacyPinException(
          'The server did not return a profile unlock.',
        );
      }
      ref
          .read(privacyUnlockedPlayersProvider.notifier)
          .unlock(widget.player.id, token);
    } on PlayerPrivacyPinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openPrivacyPinManagement() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerPrivacyPinScreen(
          player: widget.player,
          isGuardian: widget.isGuardian,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(playerPrivacyPinStatusProvider(widget.player.id));
    final unlocked = ref
        .watch(privacyUnlockedPlayersProvider)
        .contains(widget.player.id);
    return status.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: FilledButton.tonal(
          onPressed: () =>
              ref.invalidate(playerPrivacyPinStatusProvider(widget.player.id)),
          child: const Text('Retry privacy check'),
        ),
      ),
      data: (pinStatus) {
        if (unlocked) return widget.child;
        if (!pinStatus.hasPin && widget.requirePinSetup) {
          return _PinSetupPrompt(
            player: widget.player,
            pinController: _setupPinController,
            confirmController: _setupConfirmController,
            busy: _busy,
            error: _error,
            onCreate: _createPin,
          );
        }
        if (!pinStatus.hasPin) return widget.child;
        return _PinPrompt(
          player: widget.player,
          isGuardian: widget.isGuardian,
          controller: _pinController,
          busy: _busy,
          error: _error,
          locked: pinStatus.locked,
          onVerify: _verify,
          onOpenPrivacyPin: widget.isGuardian
              ? _openPrivacyPinManagement
              : null,
        );
      },
    );
  }
}

class _PinSetupPrompt extends StatelessWidget {
  const _PinSetupPrompt({
    required this.player,
    required this.pinController,
    required this.confirmController,
    required this.busy,
    required this.error,
    required this.onCreate,
  });

  final Player player;
  final TextEditingController pinController;
  final TextEditingController confirmController;
  final bool busy;
  final String? error;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.shield_outlined, size: 52),
                  const SizedBox(height: 12),
                  const Text(
                    'Create your privacy PIN',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Before you continue, create a 4–6 digit PIN for ${player.name}’s private profile.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  _setupField(pinController, 'Create PIN'),
                  const SizedBox(height: 12),
                  _setupField(confirmController, 'Confirm PIN'),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!, style: TextStyle(color: Colors.red.shade700)),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: busy ? null : onCreate,
                      child: busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Create PIN and continue'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _setupField(TextEditingController controller, String label) {
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

class _PinPrompt extends StatelessWidget {
  const _PinPrompt({
    required this.player,
    required this.isGuardian,
    required this.controller,
    required this.busy,
    required this.error,
    required this.locked,
    required this.onVerify,
    required this.onOpenPrivacyPin,
  });

  final Player player;
  final bool isGuardian;
  final TextEditingController controller;
  final bool busy;
  final String? error;
  final bool locked;
  final VoidCallback onVerify;
  final VoidCallback? onOpenPrivacyPin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    '${player.name}\'s private profile',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    locked
                        ? 'Too many attempts. Try again later.'
                        : 'Enter the player PIN to continue.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    enabled: !busy && !locked,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Privacy PIN',
                      errorText: error,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => onVerify(),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: busy || locked ? null : onVerify,
                      child: busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Unlock profile'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (onOpenPrivacyPin != null)
                    TextButton.icon(
                      onPressed: busy ? null : onOpenPrivacyPin,
                      icon: const Icon(Icons.lock_reset_outlined, size: 18),
                      label: const Text('Reset PIN in Player privacy PIN'),
                    )
                  else
                    const Text(
                      'Ask the linked guardian or coordinator to reset it.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
