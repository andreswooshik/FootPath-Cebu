import 'package:flutter/material.dart';

import '../repositories/service_locator.dart';
import 'coach_dashboard_screen.dart';
import 'guardian_dashboard_screen.dart';
import 'login_screen.dart';
import 'player_dashboard_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.profile});

  /// Profile payload from GET /api/auth/me/ (email, role, role_display, ...).
  final Map<String, dynamic> profile;

  Future<void> _signOut(BuildContext context) async {
    await ServiceLocator.authRepository.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = profile['email'] as String? ?? 'unknown';
    final role = profile['role_display'] as String? ??
        profile['role'] as String? ??
        'unknown';

    // Route each role to its dashboard; unknown roles fall through to the
    // generic placeholder below.
    final rawRole = (profile['role'] as String? ?? '').toLowerCase();
    switch (rawRole) {
      case 'coach':
        return const CoachDashboardScreen();
      case 'player':
        return const PlayerDashboardScreen();
      case 'guardian':
        return const GuardianDashboardScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('FootPath Cebu'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => _signOut(context),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.verified_user, size: 64, color: Colors.green),
            const SizedBox(height: 16),
            Text(
              'Signed in as $email',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Chip(label: Text('Role: $role')),
          ],
        ),
      ),
    );
  }
}
