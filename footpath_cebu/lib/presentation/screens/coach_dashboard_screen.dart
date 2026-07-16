import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';
import 'package:footpath_cebu/presentation/screens/player_profile_screen.dart';
import 'package:footpath_cebu/presentation/widgets/coach_bottom_nav.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/player_card.dart';

/// Coach Portal — the Active Squad Roster.
///
/// A thin View: it renders the squad/filter providers and forwards user
/// intent (search, tier filter) back to them. No data-access or business
/// logic lives here.
class CoachDashboardScreen extends ConsumerWidget {
  const CoachDashboardScreen({super.key, required this.profile});

  /// The signed-in coach, handed down from the login flow.
  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Total players registered to the squad (unfiltered) — the roster header
    // keeps reporting the true squad size while the grid shows a subset.
    final registeredCount = ref.watch(squadProvider).value?.length ?? 0;
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
      body: Column(
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
                  '$registeredCount Players Registered'
                  ' • Season 2024-2025',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                _SearchBar(
                  onChanged:
                      ref.read(rosterFilterProvider.notifier).search,
                ),
              ],
            ),
          ),
          const _TierFilterBar(),
          Expanded(child: _RosterBody(profile: profile)),
        ],
      ),
      bottomNavigationBar: CoachBottomNav(profile: profile),
    );
  }
}

/// The roster grid with its loading / error / empty states.
class _RosterBody extends ConsumerWidget {
  const _RosterBody({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(filteredSquadProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => DashboardErrorState(
            message: friendlyErrorMessage(
              e,
              'Something went wrong loading the roster.',
            ),
            onRetry: () => ref.invalidate(squadProvider),
          ),
          data: (players) {
            if (players.isEmpty) {
              return Center(
                child: Text(_emptyMessage(ref.watch(rosterFilterProvider))),
              );
            }
            return RefreshIndicator(
              onRefresh: () => ref.refresh(squadProvider.future),
              child: GridView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, // <-- the "2 columns"
                  crossAxisSpacing: 12, // horizontal gap between cards
                  mainAxisSpacing: 12, // vertical gap between rows
                  // matches the card frame's proportions
                  childAspectRatio: 600 / 850,
                ),
                itemCount: players.length,
                itemBuilder: (context, i) => PlayerCard(
                  player: players[i],
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlayerProfileScreen(
                        player: players[i],
                        profile: profile,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
  }

  /// Names the reason the grid is empty. "No players match your search" is a
  /// lie when the coach hasn't typed anything and simply picked a tier nobody
  /// is registered to yet.
  String _emptyMessage(RosterFilter filter) {
    final tier = filter.tier;
    final searching = filter.query.isNotEmpty;
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
class _TierFilterBar extends ConsumerWidget {
  const _TierFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final squad = ref.watch(squadProvider).value ?? const [];
    final filter = ref.watch(rosterFilterProvider);
    final notifier = ref.read(rosterFilterProvider.notifier);
    // How many players sit in each tier, ignoring the search query — shown on
    // the filter chips so an empty tier is obvious before the coach taps it.
    int countFor(AgeTier tier) =>
        squad.where((p) => p.ageTier == tier).length;

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          FilterChip(
            label: Text('All (${squad.length})'),
            selected: filter.tier == null,
            onSelected: (_) => notifier.filterByTier(null),
          ),
          for (final tier in AgeTier.values) ...[
            const SizedBox(width: 8),
            FilterChip(
              label: Text('${tier.label} (${countFor(tier)})'),
              selected: filter.tier == tier,
              // Re-tapping the active chip clears it, so there are two ways
              // back to the full squad.
              onSelected: (selected) =>
                  notifier.filterByTier(selected ? tier : null),
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
