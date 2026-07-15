import 'package:flutter/material.dart';

import 'package:footpath_cebu/core/di/service_locator.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/screens/player_profile_screen.dart';
import 'package:footpath_cebu/presentation/viewmodels/coach_dashboard_viewmodel.dart';
import 'package:footpath_cebu/presentation/widgets/coach_bottom_nav.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/player_card.dart';

/// Coach Portal — the Active Squad Roster.
///
/// A thin View: it renders [CoachDashboardViewModel] state and forwards user
/// intent (search) back to it. No data-access or business logic lives here.
class CoachDashboardScreen extends StatefulWidget {
  const CoachDashboardScreen({super.key, required this.profile});

  /// The signed-in coach, handed down from the login flow.
  final UserProfile profile;

  @override
  State<CoachDashboardScreen> createState() => _CoachDashboardScreenState();
}

class _CoachDashboardScreenState extends State<CoachDashboardScreen> {
  late final CoachDashboardViewModel _viewModel = CoachDashboardViewModel(
    ServiceLocator.getSquad,
  );

  @override
  void initState() {
    super.initState();
    _viewModel.loadSquad();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.sports_soccer, size: 20),
            SizedBox(width: 8),
            Text('FootPath Cebu'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            tooltip: 'Notifications',
            onPressed: () {},
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Active Squad Roster',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_viewModel.registeredCount} Players Registered'
                      ' • Season 2024-2025',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    _SearchBar(onChanged: _viewModel.search),
                  ],
                ),
              ),
              _TierFilterBar(viewModel: _viewModel),
              Expanded(child: _buildBody()),
            ],
          );
        },
      ),
      bottomNavigationBar: CoachBottomNav(profile: widget.profile),
    );
  }

  Widget _buildBody() {
    if (_viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_viewModel.error != null) {
      return DashboardErrorState(
        message: _viewModel.error!,
        onRetry: _viewModel.loadSquad,
      );
    }
    final players = _viewModel.players;
    if (players.isEmpty) {
      return Center(child: Text(_emptyMessage()));
    }
    return RefreshIndicator(
      onRefresh: _viewModel.loadSquad,
      child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, // <-- the "2 columns"
          crossAxisSpacing: 12, // horizontal gap between cards
          mainAxisSpacing: 12, // vertical gap between rows
          childAspectRatio: 600 / 850, // matches the card frame's proportions
        ),
        itemCount: players.length,
        itemBuilder: (context, i) => PlayerCard(
          player: players[i],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PlayerProfileScreen(
                player: players[i],
                profile: widget.profile,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Names the reason the grid is empty. "No players match your search" is a
  /// lie when the coach hasn't typed anything and simply picked a tier nobody
  /// is registered to yet.
  String _emptyMessage() {
    final tier = _viewModel.tierFilter;
    final searching = _viewModel.query.isNotEmpty;
    if (tier == null) {
      return searching
          ? 'No players match your search.'
          : 'No players registered yet.';
    }
    return searching
        ? 'No ${tier.label} players match your search.'
        : 'No players in ${tier.label} (${tier.ageLabel}) yet.';
  }
}

/// The age-tier filter above the roster grid.
///
/// A scrollable chip row rather than a segmented button: "All | Foundation |
/// Development | Pathway" cannot fit a phone's width without truncating, and
/// segmented buttons don't scroll — so this keeps working when a fourth tier
/// is added. Single-select, mirroring how the coach thinks ("show me the
/// Foundation squad"), and it composes with the search field above it.
class _TierFilterBar extends StatelessWidget {
  const _TierFilterBar({required this.viewModel});

  final CoachDashboardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          FilterChip(
            label: Text('All (${viewModel.registeredCount})'),
            selected: viewModel.tierFilter == null,
            onSelected: (_) => viewModel.filterByTier(null),
          ),
          for (final tier in AgeTier.values) ...[
            const SizedBox(width: 8),
            FilterChip(
              label: Text('${tier.label} (${viewModel.countFor(tier)})'),
              selected: viewModel.tierFilter == tier,
              // Re-tapping the active chip clears it, so there are two ways
              // back to the full squad.
              onSelected: (selected) =>
                  viewModel.filterByTier(selected ? tier : null),
            ),
          ],
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search player or position',
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}
