import 'package:flutter/material.dart';

const _coordinatorDestinations = [
  (Icons.home_outlined, 'Home'),
  (Icons.groups_outlined, 'People'),
  (Icons.event_note_outlined, 'Schedule'),
  (Icons.assignment_turned_in_outlined, 'Operations'),
  (Icons.person_outline, 'Profile'),
];

class CoordinatorBottomNav extends StatelessWidget {
  const CoordinatorBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) => NavigationBar(
    selectedIndex: selectedIndex,
    onDestinationSelected: onDestinationSelected,
    destinations: [
      for (final (icon, label) in _coordinatorDestinations)
        NavigationDestination(icon: Icon(icon), label: label),
    ],
  );
}

class CoordinatorNavigationRail extends StatelessWidget {
  const CoordinatorNavigationRail({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.extended = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool extended;

  @override
  Widget build(BuildContext context) => NavigationRail(
    extended: extended,
    selectedIndex: selectedIndex,
    onDestinationSelected: onDestinationSelected,
    labelType: extended
        ? NavigationRailLabelType.none
        : NavigationRailLabelType.all,
    destinations: [
      for (final (icon, label) in _coordinatorDestinations)
        NavigationRailDestination(icon: Icon(icon), label: Text(label)),
    ],
  );
}
