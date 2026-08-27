import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/screens/login_screen.dart';
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
      title: const Text('Account'),
    ),
    body: ListView(
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
                    profile.name.isEmpty ? '?' : profile.name[0].toUpperCase(),
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
        const SizedBox(height: 12),
        Card(
          child: const ListTile(
            leading: Icon(Icons.admin_panel_settings_outlined),
            title: Text('Web portal manages access'),
            subtitle: Text(
              'Use the web portal to update your password or mobile-access settings so both logins stay synchronized.',
            ),
          ),
        ),
        const SizedBox(height: 24),
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
  );
}
