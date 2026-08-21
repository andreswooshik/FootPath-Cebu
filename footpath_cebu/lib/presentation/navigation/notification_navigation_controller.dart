import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:footpath_cebu/domain/entities/notification_destination.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';

typedef NotificationProfileResolver = Future<UserProfile?> Function();
typedef NotificationOpenedMarker =
    Future<void> Function(NotificationOpenRequest request);
typedef NotificationNavigation =
    Future<void> Function(ResolvedNotificationNavigation resolved);

class ResolvedNotificationNavigation {
  const ResolvedNotificationNavigation({
    required this.destination,
    required this.profile,
  });

  final NotificationDestination destination;
  final UserProfile? profile;
}

/// Resolves the current server-authoritative profile, marks the represented
/// inbox row read best-effort, and suppresses duplicate navigation callbacks.
///
/// Widget-specific route construction stays outside this controller, which
/// makes the trust/routing policy directly testable without Firebase plugins.
class NotificationNavigationController {
  NotificationNavigationController(this._resolveProfile, this._markOpened);

  final NotificationProfileResolver _resolveProfile;
  final NotificationOpenedMarker _markOpened;
  final Set<String> _activeRequestKeys = <String>{};

  Future<bool> open(
    NotificationOpenRequest request,
    NotificationNavigation navigate,
  ) async {
    final key = request.deduplicationKey;
    if (!_activeRequestKeys.add(key)) return false;

    try {
      UserProfile? profile;
      try {
        profile = await _resolveProfile();
      } catch (error) {
        debugPrint('Could not resolve notification profile: $error');
      }

      final destination = profile == null
          ? NotificationDestination(
              kind: NotificationDestinationKind.inbox,
              request: request,
            )
          : resolveNotificationDestination(profile, request);

      unawaited(
        _markOpened(request).catchError((Object error) {
          debugPrint('Could not mark opened notification read: $error');
        }),
      );
      await navigate(
        ResolvedNotificationNavigation(
          destination: destination,
          profile: profile,
        ),
      );
      return true;
    } finally {
      _activeRequestKeys.remove(key);
    }
  }
}
