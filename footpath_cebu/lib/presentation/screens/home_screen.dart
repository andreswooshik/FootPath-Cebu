import 'package:flutter/material.dart';

import 'package:footpath_cebu/core/di/service_locator.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/screens/coach_dashboard_screen.dart';
import 'package:footpath_cebu/presentation/screens/guardian_dashboard_screen.dart';
import 'package:footpath_cebu/presentation/screens/login_screen.dart';
import 'package:footpath_cebu/presentation/screens/player_dashboard_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.profile});

  /// The signed-in user, from GET /api/auth/me/.
  final UserProfile profile;

  Future<void> _signOut(BuildContext context) async {
    await ServiceLocator.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Route each role to its dashboard; unknown roles fall through to the
    // generic placeholder below.
    switch (profile.role) {
      case 'COACH':
        return CoachDashboardScreen(profile: profile);
      case 'PLAYER':
        return const PlayerDashboardScreen();
      case 'GUARDIAN':
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
              'Signed in as ${profile.email}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Chip(label: Text('Role: ${profile.displayRole}')),
          ],
        ),
      ),
    );
  }
}
