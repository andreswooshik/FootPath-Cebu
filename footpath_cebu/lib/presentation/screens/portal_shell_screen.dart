import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/providers/guardian_dashboard_providers.dart';
import 'package:footpath_cebu/presentation/providers/player_dashboard_providers.dart';
import 'package:footpath_cebu/presentation/screens/coach_dashboard_screen.dart';
import 'package:footpath_cebu/presentation/screens/coach_profile_screen.dart';
import 'package:footpath_cebu/presentation/screens/coach_progress_screen.dart';
import 'package:footpath_cebu/presentation/screens/guardian_dashboard_screen.dart';
import 'package:footpath_cebu/presentation/screens/player_dashboard_screen.dart';
import 'package:footpath_cebu/presentation/screens/profile_tab_screen.dart';
import 'package:footpath_cebu/presentation/screens/progress_screen.dart';
import 'package:footpath_cebu/presentation/screens/schedule_tab_screen.dart';
import 'package:footpath_cebu/presentation/screens/training_schedule_screen.dart';
import 'package:footpath_cebu/presentation/widgets/coach_bottom_nav.dart';
import 'package:footpath_cebu/presentation/widgets/player_privacy_gate.dart';
import 'package:footpath_cebu/presentation/widgets/portal_bottom_nav.dart';
import 'package:footpath_cebu/presentation/widgets/portal_shell.dart';

/// The coach's persistent tab shell.
class CoachPortalScreen extends StatelessWidget {
  const CoachPortalScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return PortalShell(
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
  const PlayerPortalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider);
    return profile.maybeWhen(
      data: (player) => PortalShell(
        showNavigation: !isPlayerPrivacyGateActive(
          ref,
          player.id,
          requirePinSetup: true,
        ),
        pages: [
          const PlayerDashboardScreen(),
          ScheduleTabScreen(player: player),
          ProgressScreen(player: player),
          ProfileTabScreen(player: player),
        ],
        navigationBarBuilder: (selectedIndex, onSelected) => PortalBottomNav(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelected,
        ),
      ),
      orElse: () => const PlayerDashboardScreen(),
    );
  }
}

/// The guardian's persistent tab shell. Tabs are available only after a
/// child has been selected and unlocked, matching the existing privacy rule.
class GuardianPortalScreen extends ConsumerWidget {
  const GuardianPortalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(selectedChildProvider);
    if (player == null) return const GuardianDashboardScreen();

    return PortalShell(
      showNavigation: !isPlayerPrivacyGateActive(ref, player.id),
      pages: [
        const GuardianDashboardScreen(),
        ScheduleTabScreen(player: player, isGuardian: true),
        ProgressScreen(player: player, isGuardian: true),
        ProfileTabScreen(player: player, isGuardian: true),
      ],
      navigationBarBuilder: (selectedIndex, onSelected) => PortalBottomNav(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
      ),
    );
  }
}
