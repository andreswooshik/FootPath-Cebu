import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/guardian_dashboard_providers.dart';
import 'package:footpath_cebu/presentation/providers/player_dashboard_providers.dart';
import 'package:footpath_cebu/presentation/screens/coach_dashboard_screen.dart';
import 'package:footpath_cebu/presentation/screens/coach_profile_screen.dart';
import 'package:footpath_cebu/presentation/screens/coach_progress_screen.dart';
import 'package:footpath_cebu/presentation/screens/eligibility_history_screen.dart';
import 'package:footpath_cebu/presentation/screens/guardian_dashboard_screen.dart';
import 'package:footpath_cebu/presentation/screens/player_dashboard_screen.dart';
import 'package:footpath_cebu/presentation/screens/profile_tab_screen.dart';
import 'package:footpath_cebu/presentation/screens/progress_screen.dart';
import 'package:footpath_cebu/presentation/screens/schedule_tab_screen.dart';
import 'package:footpath_cebu/presentation/screens/training_schedule_screen.dart';
import 'package:footpath_cebu/presentation/widgets/coach_bottom_nav.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';
import 'package:footpath_cebu/presentation/widgets/player_privacy_gate.dart';
import 'package:footpath_cebu/presentation/widgets/portal_bottom_nav.dart';
import 'package:footpath_cebu/presentation/widgets/portal_shell.dart';

/// The coach's persistent tab shell.
class CoachPortalScreen extends StatelessWidget {
  const CoachPortalScreen({
    super.key,
    required this.profile,
    this.initialTabIndex = 0,
  });

  final UserProfile profile;
  final int initialTabIndex;

  @override
  Widget build(BuildContext context) {
    return PortalShell(
      initialIndex: initialTabIndex,
      pages: [
        CoachDashboardScreen(profile: profile),
        TrainingScheduleScreen(profile: profile),
        CoachProgressScreen(profile: profile),
        CoachProfileScreen(profile: profile),
      ],
      navigationBarBuilder: (selectedIndex, onSelected) => CoachBottomNav(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
      ),
    );
  }
}

/// The player's persistent tab shell. The profile provider is also used here
/// to construct the other tabs, while the dashboard continues to own its
/// existing loading and privacy-gate UI.
class PlayerPortalScreen extends ConsumerWidget {
  const PlayerPortalScreen({
    super.key,
    this.initialTabIndex = 0,
    this.openEligibility = false,
  });

  final int initialTabIndex;
  final bool openEligibility;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider);
    return profile.maybeWhen(
      data: (player) {
        final privacyGateActive = isPlayerPrivacyGateActive(
          ref,
          player.id,
          requirePinSetup: true,
        );
        return PortalShell(
          // Never use a deep link to skip the mandatory Player PIN setup.
          // didUpdateWidget moves to the requested tab after the gate opens.
          initialIndex: privacyGateActive ? 0 : initialTabIndex,
          showNavigation: !privacyGateActive,
          pages: [
            _PlayerDashboardDestination(
              player: player,
              openEligibility: openEligibility,
            ),
            ScheduleTabScreen(player: player),
            ProgressScreen(player: player),
            ProfileTabScreen(player: player),
          ],
          navigationBarBuilder: (selectedIndex, onSelected) => PortalBottomNav(
            selectedIndex: selectedIndex,
            onDestinationSelected: onSelected,
          ),
        );
      },
      orElse: () => const PlayerDashboardScreen(),
    );
  }
}

/// The guardian's persistent tab shell. Tabs are available only after a
/// child has been selected and unlocked, matching the existing privacy rule.
class GuardianPortalScreen extends ConsumerStatefulWidget {
  const GuardianPortalScreen({
    super.key,
    this.initialTabIndex = 0,
    this.initialPlayerId,
    this.selectDefaultPlayer = false,
    this.openEligibility = false,
    this.openPlayerProfile = false,
  });

  final int initialTabIndex;
  final String? initialPlayerId;
  final bool selectDefaultPlayer;
  final bool openEligibility;
  final bool openPlayerProfile;

  @override
  ConsumerState<GuardianPortalScreen> createState() =>
      _GuardianPortalScreenState();
}

class _GuardianPortalScreenState extends ConsumerState<GuardianPortalScreen> {
  bool _selectionQueued = false;
  bool _selectionApplied = false;

  @override
  void didUpdateWidget(covariant GuardianPortalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPlayerId != widget.initialPlayerId ||
        oldWidget.selectDefaultPlayer != widget.selectDefaultPlayer) {
      _selectionQueued = false;
      _selectionApplied = false;
    }
  }

  void _selectInitialPlayer(List<Player> players) {
    if (_selectionApplied ||
        _selectionQueued ||
        players.isEmpty ||
        (!widget.selectDefaultPlayer && widget.initialPlayerId == null)) {
      return;
    }
    var player = players.first;
    final requestedId = widget.initialPlayerId;
    if (requestedId != null) {
      for (final candidate in players) {
        if (candidate.id == requestedId) {
          player = candidate;
          break;
        }
      }
    }
    _selectionQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _selectionQueued = false;
      _selectionApplied = true;
      ref.read(selectedChildIdProvider.notifier).select(player.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final linkedPlayers = ref.watch(linkedPlayersProvider).value;
    if (linkedPlayers != null) _selectInitialPlayer(linkedPlayers);
    final player = ref.watch(selectedChildProvider);
    if (player == null) return const GuardianDashboardScreen();

    final privacyGateActive = isPlayerPrivacyGateActive(ref, player.id);
    return PortalShell(
      // A targeted child is selected from the authorized linked-player list,
      // but child-scoped tabs still wait behind that child's privacy gate.
      initialIndex: privacyGateActive ? 0 : widget.initialTabIndex,
      showNavigation: !privacyGateActive,
      pages: [
        _GuardianDashboardDestination(
          player: player,
          openEligibility: widget.openEligibility,
        ),
        ScheduleTabScreen(player: player, isGuardian: true),
        ProgressScreen(player: player, isGuardian: true),
        widget.openPlayerProfile
            ? _GuardianPlayerProfileDestination(player: player)
            : ProfileTabScreen(player: player, isGuardian: true),
      ],
      navigationBarBuilder: (selectedIndex, onSelected) => PortalBottomNav(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
      ),
    );
  }
}

class _GuardianPlayerProfileDestination extends StatelessWidget {
  const _GuardianPlayerProfileDestination({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return PlayerPrivacyGate(
      player: player,
      isGuardian: true,
      child: _GuardianPlayerProfileDetails(player: player),
    );
  }
}

class _GuardianPlayerProfileDetails extends ConsumerWidget {
  const _GuardianPlayerProfileDetails({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(selectedChildDetailsProvider(player.id))
        .when(
          loading: () => const DashboardLoadingState(),
          error: (error, _) => DashboardErrorState(
            message: friendlyErrorMessage(
              error,
              'Could not load the player profile.',
            ),
            onRetry: () =>
                ref.invalidate(selectedChildDetailsProvider(player.id)),
          ),
          data: (details) => ProfileTabScreen(
            player: details,
            isGuardian: true,
            showGuardianPlayerDetails: true,
          ),
        );
  }
}

class _PlayerDashboardDestination extends ConsumerStatefulWidget {
  const _PlayerDashboardDestination({
    required this.player,
    required this.openEligibility,
  });

  final Player player;
  final bool openEligibility;

  @override
  ConsumerState<_PlayerDashboardDestination> createState() =>
      _PlayerDashboardDestinationState();
}

class _PlayerDashboardDestinationState
    extends ConsumerState<_PlayerDashboardDestination> {
  bool _eligibilityQueued = false;
  bool _eligibilityOpened = false;

  void _openEligibilityWhenAllowed() {
    if (!widget.openEligibility ||
        _eligibilityQueued ||
        _eligibilityOpened ||
        isPlayerPrivacyGateActive(
          ref,
          widget.player.id,
          requirePinSetup: true,
        )) {
      return;
    }
    _eligibilityQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _eligibilityQueued = false;
      if (!mounted || _eligibilityOpened) return;
      _eligibilityOpened = true;
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          settings: const RouteSettings(name: '/eligibility-history'),
          builder: (_) => EligibilityHistoryScreen(
            playerId: widget.player.id,
            playerName: widget.player.name,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    _openEligibilityWhenAllowed();
    return const PlayerDashboardScreen();
  }
}

class _GuardianDashboardDestination extends ConsumerStatefulWidget {
  const _GuardianDashboardDestination({
    required this.player,
    required this.openEligibility,
  });

  final Player player;
  final bool openEligibility;

  @override
  ConsumerState<_GuardianDashboardDestination> createState() =>
      _GuardianDashboardDestinationState();
}

class _GuardianDashboardDestinationState
    extends ConsumerState<_GuardianDashboardDestination> {
  bool _eligibilityQueued = false;
  bool _eligibilityOpened = false;

  @override
  void didUpdateWidget(covariant _GuardianDashboardDestination oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player.id != widget.player.id) {
      _eligibilityQueued = false;
      _eligibilityOpened = false;
    }
  }

  void _openEligibilityWhenAllowed() {
    if (!widget.openEligibility ||
        _eligibilityQueued ||
        _eligibilityOpened ||
        isPlayerPrivacyGateActive(ref, widget.player.id)) {
      return;
    }
    _eligibilityQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _eligibilityQueued = false;
      if (!mounted || _eligibilityOpened) return;
      _eligibilityOpened = true;
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          settings: const RouteSettings(name: '/eligibility-history'),
          builder: (_) => EligibilityHistoryScreen(
            playerId: widget.player.id,
            playerName: widget.player.name,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    _openEligibilityWhenAllowed();
    return const GuardianDashboardScreen();
  }
}
