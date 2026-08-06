import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/player_privacy_pin_repository.dart';
import 'package:footpath_cebu/presentation/providers/player_privacy_pin_providers.dart';

/// Protects child-scoped content after a player has enabled a household PIN.
/// The unlocked state is session-only and contains no secret material.
class PlayerPrivacyGate extends ConsumerStatefulWidget {
  const PlayerPrivacyGate({
    super.key,
    required this.player,
    required this.child,
    this.isGuardian = false,
  });

  final Player player;
  final Widget child;
  final bool isGuardian;

  @override
  ConsumerState<PlayerPrivacyGate> createState() => _PlayerPrivacyGateState();
}

class _PlayerPrivacyGateState extends ConsumerState<PlayerPrivacyGate> {
  final _pinController = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pinController.dispose();
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
      await ref.read(verifyPlayerPrivacyPinProvider)(widget.player.id, pin);
      ref
          .read(privacyUnlockedPlayersProvider.notifier)
          .unlock(widget.player.id);
    } on PlayerPrivacyPinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetAsGuardian() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(resetPlayerPrivacyPinProvider)(widget.player.id);
      ref.invalidate(playerPrivacyPinStatusProvider(widget.player.id));
      ref
          .read(privacyUnlockedPlayersProvider.notifier)
          .unlock(widget.player.id);
    } on PlayerPrivacyPinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
      data: (pinStatus) => !pinStatus.hasPin || unlocked
          ? widget.child
          : _PinPrompt(
              player: widget.player,
              isGuardian: widget.isGuardian,
              controller: _pinController,
              busy: _busy,
              error: _error,
              locked: pinStatus.locked,
              onVerify: _verify,
              onReset: widget.isGuardian ? _resetAsGuardian : null,
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
    required this.onReset,
  });

  final Player player;
  final bool isGuardian;
  final TextEditingController controller;
  final bool busy;
  final String? error;
  final bool locked;
  final VoidCallback onVerify;
  final VoidCallback? onReset;

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
                  if (onReset != null) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: busy ? null : onReset,
                      child: const Text('Reset this player PIN'),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Ask the linked guardian or coordinator to reset it.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
