/// One notification stored by the FootPath backend for the signed-in user.
///
/// The `data` map contains routing identifiers only (for example `sessionId`
/// or `playerId`). Business data is loaded from its protected API when the
/// user follows a notification.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.isRead,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime createdAt;
}
