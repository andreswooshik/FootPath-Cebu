import 'package:flutter/material.dart';

import 'package:footpath_cebu/core/di/service_locator.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/screens/login_screen.dart';
import 'package:footpath_cebu/presentation/viewmodels/coach_profile_viewmodel.dart';
import 'package:footpath_cebu/presentation/widgets/coach_bottom_nav.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/stat_tile.dart';

/// Coach Portal — the signed-in coach's own profile.
///
/// A thin View over [CoachProfileViewModel]: it renders state and forwards
/// intent (refresh, reset password, sign out). No data access lives here.
class CoachProfileScreen extends StatefulWidget {
  const CoachProfileScreen({super.key, required this.profile});

  /// The signed-in user, handed down from the login flow.
  final UserProfile profile;

  @override
  State<CoachProfileScreen> createState() => _CoachProfileScreenState();
}

class _CoachProfileScreenState extends State<CoachProfileScreen> {
  late final CoachProfileViewModel _viewModel = CoachProfileViewModel(
    ServiceLocator.getSquad,
    ServiceLocator.signOut,
    ServiceLocator.sendPasswordReset,
  );

  @override
  void initState() {
    super.initState();
    _viewModel.load();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again to continue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _viewModel.signOut();
    if (!mounted) return;
    // Clear the whole stack so Back cannot return to the signed-in portal.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _changePassword() async {
    final ok = await _viewModel.sendPasswordReset(widget.profile.email);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Password reset email sent to ${widget.profile.email}.'
              : _viewModel.error ?? 'Could not send the reset email.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          return RefreshIndicator(
            onRefresh: _viewModel.load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _IdentityHeader(profile: widget.profile),
                const SizedBox(height: 24),
                _SectionTitle(title: 'Squad Snapshot'),
                const SizedBox(height: 8),
                _squadSnapshot(),
                const SizedBox(height: 24),
                _SectionTitle(title: 'Account'),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.lock_reset_outlined),
                    title: const Text('Change password'),
                    subtitle: const Text('Emails you a reset link'),
                    trailing: _viewModel.isSendingReset
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: _viewModel.isSendingReset ? null : _changePassword,
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Log out'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: Theme.of(context).colorScheme.error,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: CoachBottomNav(
        profile: widget.profile,
        selectedIndex: 3,
      ),
    );
  }

  Widget _squadSnapshot() {
    if (_viewModel.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_viewModel.error != null) {
      return DashboardErrorState(
        message: _viewModel.error!,
        onRetry: _viewModel.load,
      );
    }
    return Row(
      children: [
        Expanded(
          child: StatTile(
            icon: Icons.groups_outlined,
            label: 'Registered',
            value: '${_viewModel.registeredCount}',
            color: const Color(0xFF1B5E20),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatTile(
            icon: Icons.verified_outlined,
            label: 'Eligible',
            value: '${_viewModel.eligibleCount}',
            color: Colors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatTile(
            icon: Icons.warning_amber_rounded,
            label: 'Needs Attention',
            value: '${_viewModel.needsAttentionCount}',
            color: Colors.amber.shade800,
          ),
        ),
      ],
    );
  }
}

/// The coach's avatar, name, email and role.
class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?';
    return Column(
      children: [
        CircleAvatar(
          radius: 44,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            initial,
            style: theme.textTheme.headlineLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          profile.name,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          profile.email,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 10),
        Chip(
          avatar: const Icon(Icons.sports_soccer, size: 16),
          label: Text(profile.displayRole),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
