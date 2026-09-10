import 'package:footpath_cebu/domain/entities/app_notification.dart';
import 'package:footpath_cebu/domain/entities/page_slice.dart';

abstract class NotificationRepository {
  Future<List<AppNotification>> fetchNotifications();

  Future<PageSlice<AppNotification>> fetchNotificationPage({
    required int offset,
    required int limit,
  });

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
