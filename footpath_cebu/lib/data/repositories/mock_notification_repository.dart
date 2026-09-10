import 'package:footpath_cebu/domain/entities/app_notification.dart';
import 'package:footpath_cebu/domain/entities/page_slice.dart';
import 'package:footpath_cebu/domain/repositories/notification_repository.dart';

class MockNotificationRepository implements NotificationRepository {
  final List<AppNotification> _notifications = [];

  @override
  Future<List<AppNotification>> fetchNotifications() async =>
      List.unmodifiable(_notifications);

  @override
  Future<PageSlice<AppNotification>> fetchNotificationPage({
    required int offset,
    required int limit,
  }) async {
    final end = (offset + limit).clamp(0, _notifications.length);
    final items = offset >= _notifications.length
        ? const <AppNotification>[]
        : _notifications.sublist(offset, end);
    return PageSlice(
      items: List.unmodifiable(items),
      nextOffset: end < _notifications.length ? end : null,
    );
  }

  @override
  Future<int> fetchUnreadCount() async =>
      _notifications.where((notification) => !notification.isRead).length;

  @override
  Future<void> markAllRead() async => _notifications.clear();

  @override
  Future<void> markRead(String notificationId) async {
    _notifications.removeWhere(
      (notification) => notification.id == notificationId,
    );
  }
}
