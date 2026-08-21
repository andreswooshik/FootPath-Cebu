import 'package:flutter/material.dart';
import 'package:footpath_cebu/domain/entities/notification_destination.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/screens/home_screen.dart';

/// Enters the existing role portal at the tab/detail represented by a trusted
/// [NotificationDestination]. Protected data is still fetched by that portal.
class NotificationDestinationScreen extends StatelessWidget {
  const NotificationDestinationScreen({
    super.key,
    required this.profile,
    required this.destination,
  });

  final UserProfile profile;
  final NotificationDestination destination;

  @override
  Widget build(BuildContext context) {
    final initialTabIndex = notificationPortalTabIndex(destination);
    return KeyedSubtree(
      key: Key('notification-destination-${destination.kind.name}'),
      child: HomeScreen(
        profile: profile,
        initialPortalTabIndex: initialTabIndex,
        initialGuardianPlayerId: destination.playerId,
        selectDefaultGuardianPlayer: profile.role == 'GUARDIAN',
        openEligibility:
            destination.kind == NotificationDestinationKind.eligibility,
        openGuardianPlayerProfile:
            profile.role == 'GUARDIAN' &&
            destination.kind == NotificationDestinationKind.playerProfile,
      ),
    );
  }
}

int notificationPortalTabIndex(NotificationDestination destination) {
  return switch (destination.kind) {
    NotificationDestinationKind.schedule => 1,
    NotificationDestinationKind.playerProfile => 3,
    NotificationDestinationKind.eligibility => 0,
    NotificationDestinationKind.inbox => 0,
  };
}
