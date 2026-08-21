import 'package:footpath_cebu/domain/entities/app_notification.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';

/// The authorized application destination represented by a notification.
enum NotificationDestinationKind { schedule, playerProfile, eligibility, inbox }

/// Routing-only values carried by an inbox row or FCM data message.
///
/// IDs are hints, never authorization grants. Destination screens still load
/// protected data through the signed-in user's normal repositories.
class NotificationOpenRequest {
  const NotificationOpenRequest({
    required this.type,
    this.notificationId,
    this.sessionId,
    this.playerId,
    this.sourceMessageId,
  });

  final String type;
  final String? notificationId;
  final String? sessionId;
  final String? playerId;

  /// FCM message ID, when available, gives duplicate delivery callbacks one
  /// stable key without being used for any domain lookup.
  final String? sourceMessageId;

  factory NotificationOpenRequest.fromData(
    Map<String, dynamic> data, {
    String? sourceMessageId,
  }) {
    return NotificationOpenRequest(
      type: _text(data['type']) ?? '',
      notificationId: _text(data['notificationId']) ?? _text(data['id']),
      sessionId: _text(data['sessionId']),
      playerId: _text(data['playerId']),
      sourceMessageId: _text(sourceMessageId),
    );
  }

  factory NotificationOpenRequest.fromNotification(
    AppNotification notification,
  ) {
    return NotificationOpenRequest(
      type: notification.type,
      notificationId: notification.id,
      sessionId: _text(notification.data['sessionId']),
      playerId: _text(notification.data['playerId']),
    );
  }

  String get deduplicationKey {
    return sourceMessageId ??
        notificationId ??
        '$type|${sessionId ?? ''}|${playerId ?? ''}';
  }

  /// Matches the persisted inbox row represented by an opened FCM message.
  bool matches(AppNotification notification) {
    if (notificationId != null) return notification.id == notificationId;
    if (type.isEmpty || notification.type != type) return false;
    if (sessionId != null) {
      return _text(notification.data['sessionId']) == sessionId;
    }
    if (playerId != null) {
      return _text(notification.data['playerId']) == playerId;
    }
    return true;
  }
}

class NotificationDestination {
  const NotificationDestination({
    required this.kind,
    required this.request,
    this.playerId,
  });

  final NotificationDestinationKind kind;
  final NotificationOpenRequest request;

  /// Null for Guardian destinations means "the first currently linked child".
  /// The Guardian portal resolves that fallback from its authorized API list.
  final String? playerId;
}

/// Converts an event into a role-appropriate destination.
///
/// Player payload IDs are deliberately ignored in favor of the current
/// server-returned profile ID. Guardian IDs remain hints and are later resolved
/// against the Guardian's linked-player list. Unsupported roles stay in the
/// current-user inbox.
NotificationDestination resolveNotificationDestination(
  UserProfile profile,
  NotificationOpenRequest request,
) {
  const sessionTypes = {
    'session_scheduled',
    'session_updated',
    'session_cancelled',
  };
  if (sessionTypes.contains(request.type) &&
      const {'COACH', 'PLAYER', 'GUARDIAN'}.contains(profile.role)) {
    return NotificationDestination(
      kind: NotificationDestinationKind.schedule,
      request: request,
      playerId: profile.role == 'GUARDIAN' ? request.playerId : null,
    );
  }

  if (request.type == 'assessment_saved') {
    if (profile.role == 'PLAYER') {
      return NotificationDestination(
        kind: NotificationDestinationKind.playerProfile,
        request: request,
        playerId: profile.id,
      );
    }
    if (profile.role == 'GUARDIAN') {
      return NotificationDestination(
        kind: NotificationDestinationKind.playerProfile,
        request: request,
        playerId: request.playerId,
      );
    }
  }

  if (request.type == 'eligibility_changed') {
    if (profile.role == 'PLAYER') {
      return NotificationDestination(
        kind: NotificationDestinationKind.eligibility,
        request: request,
        playerId: profile.id,
      );
    }
    if (profile.role == 'GUARDIAN') {
      return NotificationDestination(
        kind: NotificationDestinationKind.eligibility,
        request: request,
        playerId: request.playerId,
      );
    }
  }

  return NotificationDestination(
    kind: NotificationDestinationKind.inbox,
    request: request,
  );
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
