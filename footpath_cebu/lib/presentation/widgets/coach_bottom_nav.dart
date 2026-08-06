import 'package:flutter/material.dart';

import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/screens/coach_profile_screen.dart';
import 'package:footpath_cebu/presentation/screens/coach_progress_screen.dart';
import 'package:footpath_cebu/presentation/screens/training_schedule_screen.dart';

/// The coach portal's bottom navigation, shared by every coach screen so the
/// bar looks and behaves the same everywhere.
///
/// [selectedIndex] marks the screen currently showing; tapping it is a no-op.
class CoachBottomNav extends StatelessWidget {
  const CoachBottomNav({
    super.key,
    required this.profile,
    this.selectedIndex = 0,
  });

  /// The signed-in user, needed to open the Profile destination.
  final UserProfile profile;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (i) {
        if (i == selectedIndex) return;
        switch (i) {
          case 0:
            // Squad — back to the roster this screen was opened from.
            Navigator.of(context).popUntil((route) => route.isFirst);
          case 1:
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => TrainingScheduleScreen(profile: profile),
              ),
              (route) => route.isFirst,
            );
          case 2:
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => CoachProgressScreen(profile: profile),
              ),
              (route) => route.isFirst,
            );
          case 3:
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => CoachProfileScreen(profile: profile),
              ),
              (route) => route.isFirst,
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
