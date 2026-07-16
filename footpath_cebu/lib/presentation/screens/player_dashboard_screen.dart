import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/player_dashboard_providers.dart';
import 'package:footpath_cebu/presentation/screens/login_screen.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/player_card.dart';

/// Player Portal — the signed-in player's own profile and status.
///
/// A thin View over [myProfileProvider]. Read-only: players view their own
/// data but do not edit ratings or eligibility.
class PlayerDashboardScreen extends ConsumerWidget {
  const PlayerDashboardScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await ref.read(signOutProvider)();
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => _signOut(context, ref),
          ),
        ],
      ),
      body: ref.watch(myProfileProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => DashboardErrorState(
              message: friendlyErrorMessage(
                e,
                'Something went wrong loading your profile.',
              ),
              onRetry: () => ref.invalidate(myProfileProvider),
            ),
            data: (player) => RefreshIndicator(
              onRefresh: () => ref.refresh(myProfileProvider.future),
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: PlayerCard(player: player),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _InfoTile(
                    icon: Icons.school_outlined,
                    title: 'Age Tier',
                    value: '${player.ageTier.label} • ${player.classYear}',
                  ),
                  const _SectionCard(
                    icon: Icons.event_note_outlined,
                    title: 'Schedule',
                    subtitle: 'Your upcoming training sessions appear here.',
                  ),
                  const _SectionCard(
                    icon: Icons.fact_check_outlined,
                    title: 'Attendance',
                    subtitle: 'Your attendance history appears here.',
                  ),
                  const _SectionCard(
                    icon: Icons.reviews_outlined,
                    title: 'Feedback & Ratings',
                    subtitle: 'Coach feedback and rubric ratings appear here.',
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(value),
      ),
    );
  }
}

/// Placeholder for a Day-1 feature area that later screens will fill in.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
