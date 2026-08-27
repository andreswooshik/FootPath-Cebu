import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/app_notification.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/domain/repositories/notification_repository.dart';
import 'package:footpath_cebu/presentation/navigation/notification_navigation_controller.dart';
import 'package:footpath_cebu/presentation/providers/notification_providers.dart';
import 'package:footpath_cebu/presentation/screens/notification_inbox_screen.dart';
import 'package:footpath_cebu/presentation/widgets/notification_bell.dart';

class _FakeNotificationRepository implements NotificationRepository {
  _FakeNotificationRepository()
    : notifications = [
        AppNotification(
          id: 'n1',
          type: 'session_scheduled',
          title: 'New training session',
          body: 'Open your schedule for details.',
          data: const {'sessionId': '7'},
          isRead: false,
          createdAt: DateTime.utc(2026, 8, 19, 8, 30),
        ),
      ];

  List<AppNotification> notifications;

  @override
  Future<List<AppNotification>> fetchNotifications() async => notifications;

  @override
  Future<int> fetchUnreadCount() async =>
      notifications.where((notification) => !notification.isRead).length;

  @override
  Future<void> markAllRead() async {
    notifications = notifications.map(_read).toList();
  }

  @override
  Future<void> markRead(String notificationId) async {
    notifications = notifications
        .map((item) => item.id == notificationId ? _read(item) : item)
        .toList();
  }

  AppNotification _read(AppNotification item) => AppNotification(
    id: item.id,
    type: item.type,
    title: item.title,
    body: item.body,
    data: item.data,
    isRead: true,
    createdAt: item.createdAt,
  );
}

void main() {
  testWidgets('bell shows unread count and opens the inbox', (tester) async {
    final repository = _FakeNotificationRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Scaffold(appBar: AppBar(actions: const [NotificationBell()])),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.byTooltip('Notifications, 1 unread'));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('New training session'), findsOneWidget);
    expect(find.text('Open your schedule for details.'), findsOneWidget);

    await tester.tap(find.text('New training session'));
    await tester.pumpAndSettle();
    expect(repository.notifications.single.isRead, isTrue);
    expect(find.text('Mark all read'), findsNothing);
  });

  testWidgets('push event data focuses and reads its matching inbox row', (
    tester,
  ) async {
    final repository = _FakeNotificationRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: NotificationInboxScreen(
            focusType: 'session_scheduled',
            focusSessionId: '7',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New training session'), findsOneWidget);
    expect(repository.notifications.single.isRead, isTrue);
  });

  testWidgets('known inbox row opens the role-appropriate schedule tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeNotificationRepository();
    const profile = UserProfile(
      id: 'p1',
      email: 'player@example.com',
      firstName: 'Ralf',
      lastName: 'Messi',
      role: 'PLAYER',
      roleDisplay: 'Player',
    );
    final navigation = NotificationNavigationController(() async => profile, (
      request,
    ) async {
      final notificationId = request.notificationId;
      if (notificationId != null) {
        await repository.markRead(notificationId);
      }
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(repository),
          notificationNavigationControllerProvider.overrideWithValue(
            navigation,
          ),
        ],
        child: const MaterialApp(home: NotificationInboxScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('New training session'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('notification-destination-schedule')),
      findsOneWidget,
    );
    // The deep link waits behind the Player's mandatory privacy-PIN setup.
    expect(find.text('Create your privacy PIN'), findsOneWidget);
    final pinFields = find.byType(TextField);
    await tester.enterText(pinFields.at(0), '1234');
    await tester.enterText(pinFields.at(1), '1234');
    await tester.tap(find.text('Create PIN and continue'));
    await tester.pumpAndSettle();
    // Opening the portal also starts the dashboard's mocked attendance read.
    // Drain that bounded delay so the route cannot leave a timer at teardown.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(repository.notifications.single.isRead, isTrue);
  });
}
