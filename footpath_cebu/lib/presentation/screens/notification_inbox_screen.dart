import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/domain/entities/app_notification.dart';
import 'package:footpath_cebu/domain/entities/notification_destination.dart';
import 'package:footpath_cebu/domain/repositories/notification_repository.dart';
import 'package:footpath_cebu/presentation/providers/notification_providers.dart';
import 'package:footpath_cebu/presentation/screens/notification_destination_screen.dart';
import 'package:footpath_cebu/presentation/widgets/dashboard_states.dart';

class NotificationInboxScreen extends ConsumerStatefulWidget {
  const NotificationInboxScreen({
    super.key,
    this.focusNotificationId,
    this.focusType,
    this.focusSessionId,
    this.focusPlayerId,
  });

  final String? focusNotificationId;
  final String? focusType;
  final String? focusSessionId;
  final String? focusPlayerId;

  @override
  ConsumerState<NotificationInboxScreen> createState() =>
      _NotificationInboxScreenState();
}

class _NotificationInboxScreenState
    extends ConsumerState<NotificationInboxScreen> {
  String? _autoReadId;
  bool _markingAll = false;

  Future<void> _markRead(AppNotification notification) async {
    if (notification.isRead) return;
    try {
      await ref.read(notificationActionsProvider).markRead(notification.id);
    } on NotificationRepositoryException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Could not mark this notification as read.');
    }
  }

  Future<void> _openNotification(AppNotification notification) async {
    final navigator = Navigator.of(context);
    final request = NotificationOpenRequest.fromNotification(notification);
    await ref.read(notificationNavigationControllerProvider).open(request, (
      resolved,
    ) async {
      if (!mounted || !navigator.mounted) return;
      final profile = resolved.profile;
      if (profile == null ||
          resolved.destination.kind == NotificationDestinationKind.inbox) {
        // Unknown/unsupported events already have their safest destination:
        // this focused, current-user inbox.
        return;
      }
      await navigator.push<void>(
        MaterialPageRoute(
          settings: RouteSettings(
            name: '/notifications/${resolved.destination.kind.name}',
          ),
          builder: (_) => NotificationDestinationScreen(
            profile: profile,
            destination: resolved.destination,
          ),
        ),
      );
    });
  }

  Future<void> _markAllRead() async {
    if (_markingAll) return;
    setState(() => _markingAll = true);
    try {
      await ref.read(notificationActionsProvider).markAllRead();
    } on NotificationRepositoryException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Could not mark notifications as read.');
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _readFocusedNotification(List<AppNotification> notifications) {
    for (final notification in notifications) {
      if (!_isFocused(notification)) continue;
      if (notification.id != _autoReadId && !notification.isRead) {
        _autoReadId = notification.id;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _markRead(notification);
        });
      }
      return;
    }
  }

  bool _isFocused(AppNotification notification) {
    final id = widget.focusNotificationId;
    if (id != null && notification.id == id) return true;
    final type = widget.focusType;
    if (type == null || type.isEmpty || notification.type != type) return false;
    final sessionId = widget.focusSessionId;
    if (sessionId != null && sessionId.isNotEmpty) {
      return notification.data['sessionId']?.toString() == sessionId;
    }
    final playerId = widget.focusPlayerId;
    if (playerId != null && playerId.isNotEmpty) {
      return notification.data['playerId']?.toString() == playerId;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(notificationsProvider);
    final unreadCount = ref.watch(notificationUnreadCountProvider).value ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: _markingAll ? null : _markAllRead,
              child: _markingAll
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Mark all read'),
            ),
        ],
      ),
      body: notifications.when(
        loading: () => const DashboardLoadingState(),
        error: (error, _) => DashboardErrorState(
          message: error is NotificationRepositoryException
              ? error.message
              : 'Could not load notifications.',
          onRetry: () => refreshNotificationState(ref),
        ),
        data: (items) {
          _readFocusedNotification(items);
          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => ref.refresh(notificationsProvider.future),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Icon(Icons.notifications_none, size: 56),
                  SizedBox(height: 12),
                  Center(child: Text('No notifications yet.')),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              refreshNotificationState(ref);
              await ref.read(notificationsProvider.future);
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                final focused = _isFocused(item);
                return Material(
                  color: focused
                      ? Theme.of(context).colorScheme.primaryContainer
                      : item.isRead
                      ? Colors.transparent
                      : Theme.of(context).colorScheme.surfaceContainerLow,
                  child: ListTile(
                    leading: _NotificationIcon(type: item.type),
                    title: Text(
                      item.title,
                      style: TextStyle(
                        fontWeight: item.isRead
                            ? FontWeight.normal
                            : FontWeight.w700,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item.body.isNotEmpty) Text(item.body),
                        const SizedBox(height: 4),
                        Text(
                          _formatTimestamp(item.createdAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    trailing: item.isRead
                        ? null
                        : const Icon(Icons.circle, size: 10),
                    onTap: () => _openNotification(item),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _NotificationIcon extends StatelessWidget {
  const _NotificationIcon({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final icon = switch (type) {
      'session_scheduled' ||
      'session_updated' ||
      'session_cancelled' => Icons.event_note_outlined,
      'assessment_saved' => Icons.trending_up,
      'eligibility_changed' => Icons.school_outlined,
      _ => Icons.notifications_outlined,
    };
    return CircleAvatar(child: Icon(icon, size: 20));
  }
}

String _formatTimestamp(DateTime timestamp) {
  final local = timestamp.toLocal();
  final now = DateTime.now();
  final difference = now.difference(local);
  if (!difference.isNegative && difference.inMinutes < 1) return 'Just now';
  if (!difference.isNegative && difference.inHours < 1) {
    return '${difference.inMinutes}m ago';
  }
  if (!difference.isNegative && difference.inDays < 1) {
    return '${difference.inHours}h ago';
  }
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}
