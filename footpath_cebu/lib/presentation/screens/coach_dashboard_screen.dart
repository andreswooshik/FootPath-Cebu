import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/theme/app_motion.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/domain/repositories/age_tier_repository.dart';
import 'package:footpath_cebu/presentation/providers/age_tier_providers.dart';
import 'package:footpath_cebu/presentation/providers/coach_overview_providers.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';
import 'package:footpath_cebu/presentation/providers/training_schedule_providers.dart';
import 'package:footpath_cebu/presentation/screens/log_attendance_screen.dart';
import 'package:footpath_cebu/presentation/screens/player_profile_screen.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/notification_bell.dart';
import 'package:footpath_cebu/presentation/widgets/mini_player_card.dart';
import 'package:footpath_cebu/presentation/widgets/player_card.dart';
import 'package:footpath_cebu/presentation/widgets/team_overview_card.dart';

/// Coach Portal — the Coach Dashboard: a Team Overview summary above the Active
/// Squad Roster.
///
/// A thin View: it renders the squad/overview/filter providers and forwards
/// user intent (search, tier filter, view mode) back to them. No data-access or
/// business logic lives here.
class CoachDashboardScreen extends ConsumerStatefulWidget {
  const CoachDashboardScreen({super.key, required this.profile});

  /// The signed-in coach, handed down from the login flow.
  final UserProfile profile;

  @override
  ConsumerState<CoachDashboardScreen> createState() =>
      _CoachDashboardScreenState();
}

class _CoachDashboardScreenState extends ConsumerState<CoachDashboardScreen> {
  /// Compact list of mini cards vs. the full FUT-card grid.
  bool _compact = true;

  void _openProfile(Player player) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PlayerProfileScreen(player: player, profile: widget.profile),
      ),
    );
  }

  /// Quick attendance from the roster routes the coach to a session whose
  /// roll-call is still open — the session day through two days after. When
  /// several are open, the most recent one is picked.
  void _markAttendance(Player player) {
    final all =
        ref.read(trainingSessionsProvider).value ?? const <TrainingSession>[];
    final open = all.where((s) => s.isAttendanceOpen).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (open.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No session is open for attendance right now.'),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            LogAttendanceScreen(session: open.first, profile: widget.profile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            icon: Icon(_compact ? Icons.grid_view : Icons.view_agenda_outlined),
            tooltip: _compact ? 'Card grid' : 'Compact list',
            onPressed: () => setState(() => _compact = !_compact),
          ),
          const NotificationBell(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(squadProvider.future),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _TeamOverviewSection(),
                    const SizedBox(height: 16),
                    Text(
                      'Active Squad Roster',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$registeredCount Players Registered • Season 2024-2025',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    _SearchBar(
                      onChanged: ref.read(rosterFilterProvider.notifier).search,
                    ),
                    const SizedBox(height: 8),
                    const _TierFilterBar(),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            _RosterSliver(
              compact: _compact,
              onOpenProfile: _openProfile,
              onMarkAttendance: _markAttendance,
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        ),
      ),
    ).animateScreenEntrance();
  }
}

/// The Team Overview card with its own loading/error handling.
class _TeamOverviewSection extends ConsumerWidget {
  const _TeamOverviewSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(teamOverviewProvider)
        .maybeWhen(
          data: (overview) => TeamOverviewCard(overview: overview),
          // While the squad loads, the roster below already shows a spinner —
          // keep the overview slot empty rather than doubling up.
          orElse: () => const SizedBox.shrink(),
        );
  }
}

/// The roster as either a mini-card list or a full-card grid, plus its
/// loading / error / empty states — all as slivers so it scrolls under the
/// Team Overview.
class _RosterSliver extends ConsumerWidget {
  const _RosterSliver({
    required this.compact,
    required this.onOpenProfile,
    required this.onMarkAttendance,
  });

  final bool compact;
  final ValueChanged<Player> onOpenProfile;
  final ValueChanged<Player> onMarkAttendance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(filteredSquadProvider)
        .when(
          loading: () => const SliverToBoxAdapter(
            child: DashboardLoadingState(compact: true, shrinkWrap: true),
          ),
          error: (e, _) => SliverToBoxAdapter(
            child: DashboardErrorState(
              message: friendlyErrorMessage(
                e,
                'Something went wrong loading the roster.',
              ),
              onRetry: () => ref.invalidate(squadProvider),
            ),
          ),
          data: (players) {
            if (players.isEmpty) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(48),
                  child: Center(
                    child: Text(
                      _emptyMessage(
                        ref.watch(rosterFilterProvider),
                        ref.watch(ageTierBandsProvider).value,
                      ),
                    ),
                  ),
                ),
              );
            }
            if (compact) {
              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.builder(
                  itemCount: players.length,
                  itemBuilder: (context, i) =>
                      MiniPlayerCard(
                        player: players[i],
                        onTap: () => onOpenProfile(players[i]),
                        onMarkAttendance: () => onMarkAttendance(players[i]),
                      ).animateListItem(
                        key: ValueKey('mini-${players[i].id}'),
                        index: i,
                      ),
                ),
              );
            }
            return SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 600 / 850,
                ),
                itemCount: players.length,
                itemBuilder: (context, i) =>
                    PlayerCard(
                      player: players[i],
                      onTap: () => onOpenProfile(players[i]),
                    ).animateListItem(
                      key: ValueKey('card-${players[i].id}'),
                      index: i,
                    ),
              ),
            );
          },
        );
  }

  /// Names the reason the roster is empty. "No players match your search" is a
  /// lie when the coach hasn't typed anything and simply picked a tier nobody
  /// is registered to yet.
  String _emptyMessage(RosterFilter filter, Map<AgeTier, AgeBand>? bands) {
    final tier = filter.tier;
    final searching = filter.query.isNotEmpty;
    if (tier == null) {
      return searching
          ? 'No players match your search.'
          : 'No players registered yet.';
    }
    return searching
        ? 'No ${tier.label} players match your search.'
        : 'No players in ${tier.label} (${tierAgeLabel(tier, bands)}) yet.';
  }
}

/// The age-tier filter above the roster.
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
    int countFor(AgeTier tier) => squad.where((p) => p.ageTier == tier).length;

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
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
