import 'package:flutter/material.dart';

import '../repositories/service_locator.dart';
import '../viewmodels/guardian_dashboard_viewmodel.dart';
import '../widgets/dashboard_states.dart';
import '../widgets/player_card.dart';
import 'login_screen.dart';

/// Guardian Portal — a read-only view of the guardian's linked children.
///
/// A thin View over [GuardianDashboardViewModel]. Guardians can view but never
/// edit their children's profile, attendance, ratings, or eligibility.
class GuardianDashboardScreen extends StatefulWidget {
  const GuardianDashboardScreen({super.key});

  @override
  State<GuardianDashboardScreen> createState() =>
      _GuardianDashboardScreenState();
}

class _GuardianDashboardScreenState extends State<GuardianDashboardScreen> {
  late final GuardianDashboardViewModel _viewModel =
      GuardianDashboardViewModel(ServiceLocator.playerRepository);

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
    await ServiceLocator.authRepository.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Players'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: _signOut,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          if (_viewModel.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_viewModel.error != null) {
            return DashboardErrorState(
              message: _viewModel.error!,
              onRetry: _viewModel.load,
            );
          }
          final children = _viewModel.children;
          if (children.isEmpty) {
            return const Center(child: Text('No linked players yet.'));
          }
          return RefreshIndicator(
            onRefresh: _viewModel.load,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: children.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${_viewModel.childCount} linked '
                      '${_viewModel.childCount == 1 ? "player" : "players"}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  );
                }
                return PlayerCard(player: children[i - 1]);
              },
            ),
          );
        },
      ),
    );
  }
}
