import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/screens/home_screen.dart';
import 'package:footpath_cebu/presentation/screens/login_screen.dart';

/// Restores the identity-provider session before deciding whether to show the
/// login form or the role-specific home screen. Firebase keeps its session in
/// local device storage, so closing and reopening the app does not sign the
/// user out.
class SessionBootstrapScreen extends ConsumerStatefulWidget {
  const SessionBootstrapScreen({super.key});

  /// Creates the mutable state used by this view.
  @override
  ConsumerState<SessionBootstrapScreen> createState() =>
      _SessionBootstrapScreenState();
}

class _SessionBootstrapScreenState
    extends ConsumerState<SessionBootstrapScreen> {
  UserProfile? _profile;
  String? _error;
  bool _showLogin = false;
  bool _restoring = true;

  /// Initializes the local state when this view first enters the widget tree.
  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  /// Restores the signed-in session and routes to the appropriate starting
  /// screen.
  Future<void> _restore() async {
    try {
      final profile = await ref.read(restoreSessionProvider)();
      if (!mounted) return;
      if (profile != null) {
        // Match the normal login side effects for a restored session.
        unawaited(ref.read(registerDeviceProvider)());
        ref.read(attendanceSyncServiceProvider)?.start();
      }
      setState(() {
        _profile = profile;
        _restoring = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _restoring = false;
        });
      }
    }
  }

  /// Builds the session bootstrap screen view.
  @override
  Widget build(BuildContext context) {
    if (_profile != null) return HomeScreen(profile: _profile!);
    if (_showLogin || (!_restoring && _error == null && _profile == null)) {
      return const LoginScreen();
    }
    if (_error != null) {
      return _RestoreErrorScreen(
        message: _error!,
        onContinue: () => setState(() => _showLogin = true),
      );
    }
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sports_soccer, size: 64),
            SizedBox(height: 16),
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Restoring your session...'),
          ],
        ),
      ),
    ).animateScreenEntrance();
  }
}

class _RestoreErrorScreen extends StatelessWidget {
  const _RestoreErrorScreen({required this.message, required this.onContinue});

  final String message;
  final VoidCallback onContinue;

  /// Builds the restore error screen view.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 56),
              const SizedBox(height: 16),
              const Text(
                'We could not restore your session.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onContinue,
                child: const Text('Continue to sign in'),
              ),
            ],
          ),
        ),
      ),
    ).animateScreenEntrance();
  }
}
