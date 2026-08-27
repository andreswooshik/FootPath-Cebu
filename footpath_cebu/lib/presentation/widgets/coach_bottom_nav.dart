import 'package:flutter/material.dart';

const _coachDestinations = [
  (Icons.groups, 'Squad'),
  (Icons.fitness_center, 'Training'),
  (Icons.trending_up, 'Progress'),
  (Icons.person_outline, 'Profile'),
];

/// The coach portal's bottom navigation. The portal shell owns tab state and
/// supplies the destination callback so switching tabs does not push routes.
class CoachBottomNav extends StatelessWidget {
  const CoachBottomNav({
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
        for (final (icon, label) in _coachDestinations)
          NavigationDestination(icon: Icon(icon), label: label),
      ],
    );
  }
}

class CoachNavigationRail extends StatelessWidget {
  const CoachNavigationRail({
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
        for (final (icon, label) in _coachDestinations)
          NavigationRailDestination(icon: Icon(icon), label: Text(label)),
      ],
    );
  }
}
