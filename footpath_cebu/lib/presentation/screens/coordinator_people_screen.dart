import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/club_member.dart';
import 'package:footpath_cebu/domain/entities/coordinator_person.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/club_member_providers.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';
import 'package:footpath_cebu/presentation/screens/coordinator_create_account_screen.dart';
import 'package:footpath_cebu/presentation/screens/coordinator_person_details_screen.dart';
import 'package:footpath_cebu/presentation/screens/player_profile_screen.dart';
import 'package:footpath_cebu/presentation/theme/app_theme.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/eligibility_badge.dart';
import 'package:footpath_cebu/presentation/widgets/notification_bell.dart';
import 'package:footpath_cebu/presentation/widgets/responsive_content.dart';

class CoordinatorPeopleScreen extends ConsumerStatefulWidget {
  const CoordinatorPeopleScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<CoordinatorPeopleScreen> createState() =>
      _CoordinatorPeopleScreenState();
}

class _CoordinatorPeopleScreenState
    extends ConsumerState<CoordinatorPeopleScreen> {
  String _query = '';
  String _activeTab = 'Players';

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(squadProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('People'),
        actions: [
          const NotificationBell(),
          IconButton(
            tooltip: 'Create account',
            icon: const Icon(Icons.add),
            onPressed: _openCreateAccount,
          ),
        ],
      ),
      body: _activeTab == 'Players'
          ? roster.when(
              loading: () => const DashboardLoadingState(),
              error: (error, _) => DashboardErrorState(
                message: friendlyErrorMessage(
                  error,
                  'Could not load the club roster.',
                ),
                onRetry: () => ref.invalidate(squadProvider),
              ),
              data: (players) {
                final filtered = _filter(players);
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(squadProvider.future),
                  child: ResponsiveContent(
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                      itemCount: filtered.isEmpty ? 2 : filtered.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _PeopleHeader(
                            count: players.length,
                            activeTab: _activeTab,
                            onTabChanged: (value) => setState(() {
                              _activeTab = value;
                              _query = '';
                            }),
                            onChanged: (value) =>
                                setState(() => _query = value),
                          );
                        }
                        if (index == 1 && filtered.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 48),
                            child: DashboardEmptyState(
                              icon: Icons.person_search_outlined,
                              title: 'No matching people',
                              message: 'Try a different search or tab.',
                              compact: true,
                            ),
                          );
                        }
                        final player = filtered[index - 1];
                        return _PlayerRow(
                          player: player,
                          onTap: () => _openPlayerProfile(player),
                        );
                      },
                    ),
                  ),
                );
              },
            )
          : _MemberDirectory(
              role: _activeTab == 'Guardians'
                  ? ClubMemberRole.guardian
                  : ClubMemberRole.coach,
              activeTab: _activeTab,
              query: _query,
              onTabChanged: (value) => setState(() {
                _activeTab = value;
                _query = '';
              }),
              onChanged: (value) => setState(() => _query = value),
              onPersonTap: (member) => _openDetails(
                member.role == ClubMemberRole.guardian
                    ? CoordinatorPersonRole.guardian
                    : CoordinatorPersonRole.coach,
                member.id,
              ),
            ),
    );
  }

  Future<void> _openCreateAccount() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const CoordinatorCreateAccountScreen()),
    );
    if (!mounted) return;
    _invalidatePeople();
  }

  Future<void> _openDetails(CoordinatorPersonRole role, String personId) async {
    final deletedRole = await Navigator.of(context).push<CoordinatorPersonRole>(
      MaterialPageRoute(
        builder: (_) =>
            CoordinatorPersonDetailsScreen(role: role, personId: personId),
      ),
    );
    if (!mounted) return;
    _invalidatePeople();
    if (deletedRole == null) return;
    final message = deletedRole == CoordinatorPersonRole.player
        ? 'Player deleted successfully.'
        : '${deletedRole.label} account deleted successfully.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openPlayerProfile(Player player) async {
    final deletedRole = await Navigator.of(context).push<CoordinatorPersonRole>(
      MaterialPageRoute(
        builder: (_) =>
            PlayerProfileScreen(player: player, profile: widget.profile),
      ),
    );
    if (!mounted) return;
    _invalidatePeople();
    if (deletedRole != CoordinatorPersonRole.player) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Player deleted successfully.')),
    );
  }

  void _invalidatePeople() {
    ref.invalidate(squadProvider);
    ref.invalidate(clubMembersProvider(ClubMemberRole.guardian));
    ref.invalidate(clubMembersProvider(ClubMemberRole.coach));
  }

  List<Player> _filter(List<Player> players) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return players;
    return players
        .where((player) {
          return player.name.toLowerCase().contains(query) ||
              (player.position?.label.toLowerCase().contains(query) ?? false) ||
              (player.position?.code.toLowerCase().contains(query) ?? false);
        })
        .toList(growable: false);
  }
}

class _PeopleHeader extends StatelessWidget {
  const _PeopleHeader({
    required this.count,
    required this.activeTab,
    required this.onTabChanged,
    required this.onChanged,
  });

  final int count;
  final String activeTab;
  final ValueChanged<String> onTabChanged;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final tab in ['Players', 'Guardians', 'Coaches'])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: OutlinedButton(
                    onPressed: () => onTabChanged(tab),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: activeTab == tab
                          ? Colors.white
                          : const Color(0xFFF0EFEA),
                      foregroundColor: activeTab == tab
                          ? AppColors.tealDark
                          : const Color(0xFF6B6A66),
                      side: BorderSide(
                        color: activeTab == tab
                            ? AppColors.teal
                            : Colors.transparent,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(tab),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '$count ${_countLabel(activeTab, count)}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search ${activeTab.toLowerCase()}',
            prefixIcon: Icon(Icons.search),
          ),
        ),
      ],
    ),
  );
}

class _MemberDirectory extends ConsumerWidget {
  const _MemberDirectory({
    required this.role,
    required this.activeTab,
    required this.query,
    required this.onTabChanged,
    required this.onChanged,
    required this.onPersonTap,
  });

  final ClubMemberRole role;
  final String activeTab;
  final String query;
  final ValueChanged<String> onTabChanged;
  final ValueChanged<String> onChanged;
  final ValueChanged<ClubMember> onPersonTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(clubMembersProvider(role));
    return members.when(
      loading: () => const DashboardLoadingState(),
      error: (error, _) => DashboardErrorState(
        message: friendlyErrorMessage(error, 'Could not load club members.'),
        onRetry: () => ref.invalidate(clubMembersProvider(role)),
      ),
      data: (rows) {
        final normalized = query.trim().toLowerCase();
        final filtered = rows
            .where((member) {
              return normalized.isEmpty ||
                  member.name.toLowerCase().contains(normalized) ||
                  member.email.toLowerCase().contains(normalized) ||
                  member.linkedPlayers.any(
                    (player) => player.toLowerCase().contains(normalized),
                  );
            })
            .toList(growable: false);
        return RefreshIndicator(
          onRefresh: () => ref.refresh(clubMembersProvider(role).future),
          child: ResponsiveContent(
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              itemCount: filtered.isEmpty ? 2 : filtered.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _PeopleHeader(
                    count: rows.length,
                    activeTab: activeTab,
                    onTabChanged: onTabChanged,
                    onChanged: onChanged,
                  );
                }
                if (filtered.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 48),
                    child: DashboardEmptyState(
                      icon: Icons.person_search_outlined,
                      title: 'No matching people',
                      message: 'Try a different search or tab.',
                      compact: true,
                    ),
                  );
                }
                final member = filtered[index - 1];
                return _MemberRow(
                  member: member,
                  onTap: () => onPersonTap(member),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.onTap});
  final ClubMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final linked = member.linkedPlayers;
    final detail = member.role == ClubMemberRole.guardian
        ? linked.isEmpty
              ? 'No linked players'
              : linked.join(', ')
        : member.email;
    return Material(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 5,
            ),
            leading: CircleAvatar(
              radius: 19,
              backgroundColor: member.role == ClubMemberRole.coach
                  ? AppColors.teal
                  : AppColors.coral,
              child: Text(
                _initials(member.name),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            title: Text(member.name),
            subtitle: Text(detail),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  String _initials(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();
}

String _countLabel(String activeTab, int count) {
  final singular = switch (activeTab) {
    'Guardians' => 'guardian',
    'Coaches' => 'coach',
    _ => 'player',
  };
  if (count == 1) return singular;
  return singular == 'coach' ? 'coaches' : '${singular}s';
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player, required this.onTap});

  final Player player;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 5,
          ),
          leading: CircleAvatar(
            radius: 19,
            backgroundImage: player.photoUrl == null
                ? null
                : NetworkImage(player.photoUrl!),
            child: player.photoUrl == null
                ? Text(_initials(player.name))
                : null,
          ),
          title: Text(
            player.name,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${player.position?.label ?? 'Position not assigned'} · ${player.ageTier.label}',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 4),
              EligibilityBadge(
                status: player.eligibility,
                applicable: player.academicEligibilityApplicable,
              ),
            ],
          ),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
        const Divider(height: 1),
      ],
    ),
  );

  String _initials(String name) {
    final pieces = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((piece) => piece.isNotEmpty);
    return pieces.take(2).map((piece) => piece[0].toUpperCase()).join();
  }
}
