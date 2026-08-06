import 'package:flutter/material.dart';

/// The Player/Guardian portal's bottom navigation. The portal shell owns tab
/// state and supplies the destination callback so switching tabs does not
/// push routes.
class PortalBottomNav extends StatelessWidget {
  const PortalBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
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
