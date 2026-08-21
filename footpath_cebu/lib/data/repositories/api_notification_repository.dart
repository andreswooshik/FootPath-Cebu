import 'dart:convert';

import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/domain/entities/app_notification.dart';
import 'package:footpath_cebu/domain/repositories/notification_repository.dart';

class ApiNotificationRepository implements NotificationRepository {
  ApiNotificationRepository({AuthenticatedApiClient? api})
    : _api = api ?? AuthenticatedApiClient.shared;

  static const _path = '/api/notifications/';

  final AuthenticatedApiClient _api;

  @override
  Future<List<AppNotification>> fetchNotifications() async {
    try {
      final response = await _api.get(_path);
      final decoded = jsonDecode(response.body);
      final rows = decoded is Map<String, dynamic>
          ? (decoded['results'] as List? ?? const [])
          : (decoded as List? ?? const []);
      return rows
          .whereType<Map>()
          .map(
            (row) => AppNotification.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } on ApiException catch (error) {
      throw NotificationRepositoryException(error.message);
    }
  }

  @override
  Future<int> fetchUnreadCount() async {
    try {
      final response = await _api.get('${_path}unread-count/');
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final count = decoded['unreadCount'] ?? decoded['count'] ?? 0;
      return count is int ? count : int.tryParse('$count') ?? 0;
    } on ApiException catch (error) {
      throw NotificationRepositoryException(error.message);
    }
  }

  @override
  Future<void> markRead(String notificationId) async {
    try {
      await _api.patch(
        '$_path$notificationId/read/',
        expectedStatuses: const {200, 204},
      );
    } on ApiException catch (error) {
      throw NotificationRepositoryException(error.message);
    }
  }

  @override
  Future<void> markAllRead() async {
    try {
      await _api.post('${_path}read-all/', expectedStatuses: const {200, 204});
    } on ApiException catch (error) {
      throw NotificationRepositoryException(error.message);
    }
  }
}
