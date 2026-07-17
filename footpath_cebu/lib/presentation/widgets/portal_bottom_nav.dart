import 'package:flutter/material.dart';

import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/presentation/screens/profile_tab_screen.dart';
import 'package:footpath_cebu/presentation/screens/progress_screen.dart';
import 'package:footpath_cebu/presentation/screens/schedule_tab_screen.dart';

/// The Player/Guardian portal's bottom navigation, shared by every
/// Dashboard/Schedule/Progress/Profile screen so the bar looks and behaves
/// the same everywhere (mirrors [CoachBottomNav]).
///
/// [selectedIndex] marks the screen currently showing; tapping it is a no-op.
class PortalBottomNav extends StatelessWidget {
  const PortalBottomNav({
    super.key,
    required this.player,
    this.selectedIndex = 0,
  });

  /// The player this portal shows — the signed-in player themselves, or the
  /// guardian's linked child.
  final Player player;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (i) {
        if (i == selectedIndex) return;
        switch (i) {
          case 0:
            // Dashboard — back to the screen this bar was opened from.
            Navigator.of(context).popUntil((route) => route.isFirst);
          case 1:
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ScheduleTabScreen()),
            );
          case 2:
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ProgressScreen(player: player),
              ),
            );
          case 3:
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ProfileTabScreen(player: player),
              ),
            );
        }
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          label: 'Dashboard',
        ),
        NavigationDestination(
          icon: Icon(Icons.event_note_outlined),
          label: 'Schedule',
        ),
        NavigationDestination(icon: Icon(Icons.trending_up), label: 'Progress'),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Profile',
        ),
      ],
    );
  }
}
