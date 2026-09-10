import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/core/di/providers.dart'
    show notificationRepositoryProvider, restoreSessionProvider;
import 'package:footpath_cebu/domain/entities/app_notification.dart';
import 'package:footpath_cebu/domain/repositories/notification_repository.dart';
import 'package:footpath_cebu/presentation/navigation/notification_navigation_controller.dart';

export 'package:footpath_cebu/core/di/providers.dart'
    show notificationRepositoryProvider;

class NotificationListState {
  const NotificationListState({
    required this.items,
    required this.nextOffset,
    this.isLoadingMore = false,
    this.loadMoreError,
  });

  final List<AppNotification> items;
  final int? nextOffset;
  final bool isLoadingMore;
  final Object? loadMoreError;

  bool get hasMore => nextOffset != null;

  NotificationListState copyWith({
    bool? isLoadingMore,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) => NotificationListState(
    items: items,
    nextOffset: nextOffset,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    loadMoreError: clearLoadMoreError
        ? null
        : loadMoreError ?? this.loadMoreError,
  );
}

// Auto-dispose is a privacy boundary as well as a lifecycle optimization: no
// previous account's in-memory inbox/count may survive after its screens leave
// the tree and a different Firebase user signs in on the same device.
class NotificationListController extends AsyncNotifier<NotificationListState> {
  static const pageSize = 50;

  @override
  Future<NotificationListState> build() => _firstPage();

  Future<NotificationListState> _firstPage() async {
    final page = await ref
        .read(notificationRepositoryProvider)
        .fetchNotificationPage(offset: 0, limit: pageSize);
    return NotificationListState(
      items: page.items,
      nextOffset: page.nextOffset,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(_firstPage);
    if (ref.mounted) state = result;
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) return;
    state = AsyncData(
      current.copyWith(isLoadingMore: true, clearLoadMoreError: true),
    );
    try {
      final page = await ref
          .read(notificationRepositoryProvider)
          .fetchNotificationPage(offset: current.nextOffset!, limit: pageSize);
      if (!ref.mounted) return;
      state = AsyncData(
        NotificationListState(
          items: List.unmodifiable([...current.items, ...page.items]),
          nextOffset: page.nextOffset,
        ),
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = AsyncData(
        current.copyWith(isLoadingMore: false, loadMoreError: error),
      );
    }
  }
}

final notificationsProvider =
    AsyncNotifierProvider.autoDispose<
      NotificationListController,
      NotificationListState
    >(NotificationListController.new);

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
