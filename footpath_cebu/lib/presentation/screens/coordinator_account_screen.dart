import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/screens/change_password_screen.dart';
import 'package:footpath_cebu/presentation/screens/login_screen.dart';
import 'package:footpath_cebu/presentation/widgets/responsive_content.dart';
import 'package:footpath_cebu/presentation/widgets/sign_out_confirmation.dart';

class CoordinatorAccountScreen extends ConsumerWidget {
  const CoordinatorAccountScreen({super.key, required this.profile});

  final UserProfile profile;

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    if (!await confirmSignOut(context) || !context.mounted) return;
    await ref.read(unregisterDeviceProvider)();
    await ref.read(signOutProvider)();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      title: const Text('Profile'),
    ),
    body: ResponsiveContent(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 34,
                    child: Text(
                      profile.name.isEmpty
                          ? '?'
                          : profile.name[0].toUpperCase(),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    profile.name,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(profile.email, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Chip(label: Text(profile.displayRole)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Account', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_reset_outlined),
              title: const Text('Change password'),
              subtitle: const Text('Requires your current password'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChangePasswordScreen(email: profile.email),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Access', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Card(
            child: ListTile(
              leading: Icon(Icons.admin_panel_settings_outlined),
              title: Text('Mobile access'),
              subtitle: Text(
                'Club role and mobile-access permissions are managed in the web portal.',
              ),
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => _signOut(context, ref),
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    ),
  ).animateScreenEntrance();
}
