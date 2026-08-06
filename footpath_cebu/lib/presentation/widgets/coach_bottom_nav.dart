import 'package:flutter/material.dart';

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
      destinations: const [
        NavigationDestination(icon: Icon(Icons.groups), label: 'Squad'),
        NavigationDestination(
          icon: Icon(Icons.fitness_center),
          label: 'Training',
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
