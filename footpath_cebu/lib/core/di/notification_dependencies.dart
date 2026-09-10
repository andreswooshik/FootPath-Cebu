import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/core/di/runtime_config.dart';
import 'package:footpath_cebu/data/repositories/api_notification_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_notification_repository.dart';
import 'package:footpath_cebu/domain/repositories/notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) =>
      useMockData ? MockNotificationRepository() : ApiNotificationRepository(),
);
