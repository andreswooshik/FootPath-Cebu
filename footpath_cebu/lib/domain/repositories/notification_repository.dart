import 'package:footpath_cebu/domain/entities/app_notification.dart';

abstract class NotificationRepository {
  Future<List<AppNotification>> fetchNotifications();

  Future<int> fetchUnreadCount();

  Future<void> markRead(String notificationId);

  Future<void> markAllRead();
}

class NotificationRepositoryException implements Exception {
  const NotificationRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
