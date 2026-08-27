import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/screens/login_screen.dart';
import 'package:footpath_cebu/presentation/screens/portal_shell_screen.dart';
import 'package:footpath_cebu/presentation/widgets/sign_out_confirmation.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    super.key,
    required this.profile,
    this.initialPortalTabIndex = 0,
    this.initialGuardianPlayerId,
    this.selectDefaultGuardianPlayer = false,
    this.openEligibility = false,
    this.openGuardianPlayerProfile = false,
  });

  /// The signed-in user, from GET /api/auth/me/.
  final UserProfile profile;
  final int initialPortalTabIndex;
  final String? initialGuardianPlayerId;
  final bool selectDefaultGuardianPlayer;
  final bool openEligibility;
  final bool openGuardianPlayerProfile;

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    if (!await confirmSignOut(context) || !context.mounted) return;
    await ref.read(unregisterDeviceProvider)();
    await ref.read(signOutProvider)();
    if (!context.mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Route each role to its dashboard; unknown roles fall through to the
    // generic placeholder below.
    switch (profile.role) {
      case 'COORDINATOR':
        return CoordinatorPortalScreen(
          profile: profile,
          initialTabIndex: initialPortalTabIndex,
        );
      case 'COACH':
        return CoachPortalScreen(
          profile: profile,
          initialTabIndex: initialPortalTabIndex,
        );
      case 'PLAYER':
        return PlayerPortalScreen(
          initialTabIndex: initialPortalTabIndex,
          openEligibility: openEligibility,
        );
      case 'GUARDIAN':
        return GuardianPortalScreen(
          initialTabIndex: initialPortalTabIndex,
          initialPlayerId: initialGuardianPlayerId,
          selectDefaultPlayer: selectDefaultGuardianPlayer,
          openEligibility: openEligibility,
          openPlayerProfile: openGuardianPlayerProfile,
        );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('FootPath Cebu'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => _signOut(context, ref),
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
    ).animateScreenEntrance();
  }
}
