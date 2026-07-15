import 'package:flutter/material.dart';

import 'package:footpath_cebu/presentation/screens/training_schedule_screen.dart';

/// The coach portal's bottom navigation, shared by the detail screens pushed
/// from the squad roster (Player Profile, Edit Performance Data). Mirrors the
/// destinations on the Coach dashboard so the bar looks the same everywhere.
class CoachBottomNav extends StatelessWidget {
  const CoachBottomNav({super.key});

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: 0,
      onDestinationSelected: (i) {
        if (i == 0) {
          // Squad — back to the roster the detail screen was opened from.
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else if (i == 1) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const TrainingScheduleScreen()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Coming soon.')),
          );
        }
      },
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
