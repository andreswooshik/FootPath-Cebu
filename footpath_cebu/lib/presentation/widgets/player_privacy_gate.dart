import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/player_privacy_pin_repository.dart';
import 'package:footpath_cebu/presentation/providers/player_privacy_pin_providers.dart';
import 'package:footpath_cebu/presentation/screens/player_privacy_pin_screen.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/privacy_pin_ui.dart';

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
  final _pinFocus = FocusNode();
  final _setupPinFocus = FocusNode();
  final _setupConfirmFocus = FocusNode();
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
    _pinFocus.dispose();
    _setupPinFocus.dispose();
    _setupConfirmFocus.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy) return;
    final pin = _pinController.text;
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      setState(() => _error = 'Enter your 4 to 6 digit PIN.');
      _pinFocus.requestFocus();
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
    if (_busy) return;
    final pin = _setupPinController.text;
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      setState(() => _error = 'PIN must contain 4 to 6 digits.');
      _setupPinFocus.requestFocus();
      return;
    }
    if (pin != _setupConfirmController.text) {
      setState(() => _error = 'PINs do not match. Try entering them again.');
      _setupConfirmFocus.requestFocus();
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

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(playerPrivacyPinStatusProvider(widget.player.id));
    final unlocked = ref
        .watch(privacyUnlockedPlayersProvider)
        .contains(widget.player.id);
    return status.when(
      loading: () => const DashboardLoadingState(compact: true),
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
            pinFocus: _setupPinFocus,
            confirmFocus: _setupConfirmFocus,
            busy: _busy,
            error: _error,
            onCreate: _createPin,
            onClearError: _clearError,
          );
        }
        if (!pinStatus.hasPin) return widget.child;
        return _PinPrompt(
          player: widget.player,
          controller: _pinController,
          focusNode: _pinFocus,
          busy: _busy,
          error: _error,
          locked: pinStatus.locked,
          onVerify: _verify,
          onClearError: _clearError,
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
    required this.pinFocus,
    required this.confirmFocus,
    required this.busy,
    required this.error,
    required this.onCreate,
    required this.onClearError,
  });

  final Player player;
  final TextEditingController pinController;
  final TextEditingController confirmController;
  final FocusNode pinFocus;
  final FocusNode confirmFocus;
  final bool busy;
  final String? error;
  final VoidCallback onCreate;
  final VoidCallback onClearError;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final useWideLayout = size.width >= 700 && size.height < 760;
    return PrivacyPinPanel(
      maxWidth: useWideLayout ? 760 : 560,
      child: AutofillGroup(
        child: useWideLayout
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildHeader()),
                  const SizedBox(width: 32),
                  Expanded(child: _buildForm(context)),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 20),
                  _buildForm(context),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrivacyPinHeader(
          title: 'Create your privacy PIN',
          description:
              'Protect ${player.name}’s private profile before you continue.',
          icon: Icons.shield_outlined,
        ),
        const SizedBox(height: 24),
        const PrivacyPinGuidance(),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Choose your PIN', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Enter it twice to make sure it is correct.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        PrivacyPinField(
          controller: pinController,
          focusNode: pinFocus,
          label: 'New privacy PIN',
          enabled: !busy,
          autofocus: true,
          onChanged: (_) => onClearError(),
          onSubmitted: (_) => confirmFocus.requestFocus(),
        ),
        const SizedBox(height: 14),
        PrivacyPinField(
          controller: confirmController,
          focusNode: confirmFocus,
          label: 'Confirm privacy PIN',
          enabled: !busy,
          textInputAction: TextInputAction.done,
          onChanged: (_) => onClearError(),
          onSubmitted: (_) {
            if (!busy) onCreate();
          },
        ),
        if (error != null) ...[
          const SizedBox(height: 14),
          PrivacyPinErrorBanner(message: error!),
        ],
        const SizedBox(height: 22),
        PrivacyPinPrimaryButton(
          label: 'Create PIN and continue',
          onPressed: onCreate,
          busy: busy,
          icon: Icons.lock_rounded,
        ),
        const SizedBox(height: 14),
        Text(
          'You can change this later from Profile → Privacy PIN.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PinPrompt extends StatelessWidget {
  const _PinPrompt({
    required this.player,
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.error,
    required this.locked,
    required this.onVerify,
    required this.onClearError,
    required this.onOpenPrivacyPin,
  });

  final Player player;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final String? error;
  final bool locked;
  final VoidCallback onVerify;
  final VoidCallback onClearError;
  final VoidCallback? onOpenPrivacyPin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PrivacyPinPanel(
      maxWidth: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrivacyPinHeader(
            title: '${player.name}’s private profile',
            description: locked
                ? 'This PIN is temporarily locked after too many attempts. Please try again later.'
                : 'Enter the household privacy PIN to securely continue.',
            icon: locked ? Icons.lock_clock_outlined : Icons.lock_outline,
            badgeLabel: locked ? 'TEMPORARILY LOCKED' : 'PIN REQUIRED',
          ),
          const SizedBox(height: 24),
          PrivacyPinField(
            controller: controller,
            focusNode: focusNode,
            label: 'Privacy PIN',
            enabled: !busy && !locked,
            autofocus: !locked,
            textInputAction: TextInputAction.done,
            onChanged: (_) => onClearError(),
            onSubmitted: (_) {
              if (!busy && !locked) onVerify();
            },
          ),
          if (error != null) ...[
            const SizedBox(height: 14),
            PrivacyPinErrorBanner(message: error!),
          ],
          const SizedBox(height: 20),
          PrivacyPinPrimaryButton(
            label: 'Unlock profile',
            onPressed: locked ? null : onVerify,
            busy: busy,
            icon: Icons.lock_open_rounded,
          ),
          const SizedBox(height: 10),
          if (onOpenPrivacyPin != null)
            TextButton.icon(
              onPressed: busy ? null : onOpenPrivacyPin,
              icon: const Icon(Icons.lock_reset_outlined, size: 18),
              label: const Text('Reset PIN in Player privacy PIN'),
            )
          else
            Text(
              'Need help? Ask the linked guardian or coordinator to reset the PIN.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
