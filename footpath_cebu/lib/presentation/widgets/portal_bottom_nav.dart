import 'package:flutter/material.dart';

const _portalDestinations = [
  (Icons.dashboard_outlined, 'Dashboard'),
  (Icons.event_note_outlined, 'Schedule'),
  (Icons.trending_up_outlined, 'Progress'),
  (Icons.person_outline, 'Profile'),
];

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
      destinations: [
        for (final (icon, label) in _portalDestinations)
          NavigationDestination(icon: Icon(icon), label: label),
      ],
    );
  }
}

class PortalNavigationRail extends StatelessWidget {
  const PortalNavigationRail({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.extended = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      extended: extended,
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      labelType: extended
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      destinations: [
        for (final (icon, label) in _portalDestinations)
          NavigationRailDestination(icon: Icon(icon), label: Text(label)),
      ],
    );
  }
}
