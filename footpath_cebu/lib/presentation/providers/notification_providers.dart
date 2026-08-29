import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/core/di/providers.dart'
    show notificationRepositoryProvider, restoreSessionProvider;
import 'package:footpath_cebu/domain/entities/app_notification.dart';
import 'package:footpath_cebu/domain/repositories/notification_repository.dart';
import 'package:footpath_cebu/presentation/navigation/notification_navigation_controller.dart';

export 'package:footpath_cebu/core/di/providers.dart'
    show notificationRepositoryProvider;

// Auto-dispose is a privacy boundary as well as a lifecycle optimization: no
// previous account's in-memory inbox/count may survive after its screens leave
// the tree and a different Firebase user signs in on the same device.
final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>(
  (ref) => ref.watch(notificationRepositoryProvider).fetchNotifications(),
);

final notificationUnreadCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(notificationRepositoryProvider).fetchUnreadCount(),
);

class NotificationActions {
  NotificationActions(this._repository, this._refresh);

  final NotificationRepository _repository;
  final void Function() _refresh;

  Future<void> markRead(String notificationId) async {
    await _repository.markRead(notificationId);
    _refresh();
  }

  Future<void> markAllRead() async {
    await _repository.markAllRead();
    _refresh();
  }
}

final notificationActionsProvider = Provider<NotificationActions>((ref) {
  return NotificationActions(ref.watch(notificationRepositoryProvider), () {
    ref.invalidate(notificationsProvider);
    ref.invalidate(notificationUnreadCountProvider);
  });
});

final notificationNavigationControllerProvider =
    Provider<NotificationNavigationController>((ref) {
      return NotificationNavigationController(
        // Re-check `/api/auth/me/` instead of trusting whichever portal happens
        // to be under the push route. Role and account state remain server-led.
        () => ref.read(restoreSessionProvider)(),
        (request) async {
          final repository = ref.read(notificationRepositoryProvider);
          var notificationId = request.notificationId;
          if (notificationId == null) {
            final notifications = await repository.fetchNotifications();
            for (final notification in notifications) {
              if (request.matches(notification)) {
                notificationId = notification.id;
                break;
              }
            }
          }
          if (notificationId == null) return;
          await repository.markRead(notificationId);
          ref.invalidate(notificationsProvider);
          ref.invalidate(notificationUnreadCountProvider);
        },
      );
    });

void refreshNotificationState(WidgetRef ref) {
  ref.invalidate(notificationsProvider);
  ref.invalidate(notificationUnreadCountProvider);
}
