import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/app_notification.dart';
import 'package:footpath_cebu/domain/entities/notification_destination.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/presentation/navigation/notification_navigation_controller.dart';
import 'package:footpath_cebu/presentation/screens/notification_destination_screen.dart';
import 'package:footpath_cebu/presentation/widgets/portal_shell.dart';

const _player = UserProfile(
  id: '11',
  email: 'player@example.com',
  firstName: 'Player',
  lastName: 'One',
  role: 'PLAYER',
  roleDisplay: 'Player',
);

const _guardian = UserProfile(
  id: '21',
  email: 'guardian@example.com',
  firstName: 'Guardian',
  lastName: 'One',
  role: 'GUARDIAN',
  roleDisplay: 'Guardian',
);

const _coach = UserProfile(
  id: '31',
  email: 'coach@example.com',
  firstName: 'Coach',
  lastName: 'One',
  role: 'COACH',
  roleDisplay: 'Coach',
);

const _schoolStaff = UserProfile(
  id: '41',
  email: 'staff@example.com',
  firstName: 'Staff',
  lastName: 'One',
  role: 'SCHOOL_STAFF',
  roleDisplay: 'School Staff',
);

void main() {
  group('notification destination policy', () {
    test('session events enter the schedule for each mobile portal role', () {
      for (final profile in [_coach, _player, _guardian]) {
        final destination = resolveNotificationDestination(
          profile,
          const NotificationOpenRequest(
            type: 'session_updated',
            sessionId: '7',
          ),
        );
        expect(destination.kind, NotificationDestinationKind.schedule);
      }
    });

    test(
      'Player assessment routes to the signed-in Player, not payload ID',
      () {
        final destination = resolveNotificationDestination(
          _player,
          const NotificationOpenRequest(
            type: 'assessment_saved',
            playerId: 'someone-else',
          ),
        );

        expect(destination.kind, NotificationDestinationKind.playerProfile);
        expect(destination.playerId, _player.id);
      },
    );

    test('Guardian assessment uses linked-player hint or default child', () {
      final targeted = resolveNotificationDestination(
        _guardian,
        const NotificationOpenRequest(type: 'assessment_saved', playerId: '12'),
      );
      final fallback = resolveNotificationDestination(
        _guardian,
        const NotificationOpenRequest(type: 'assessment_saved'),
      );

      expect(targeted.kind, NotificationDestinationKind.playerProfile);
      expect(targeted.playerId, '12');
      expect(fallback.playerId, isNull);
      expect(notificationPortalTabIndex(targeted), 3);
    });

    test('eligibility routes only Player and Guardian roles', () {
      final playerDestination = resolveNotificationDestination(
        _player,
        const NotificationOpenRequest(
          type: 'eligibility_changed',
          playerId: 'someone-else',
        ),
      );
      final guardianDestination = resolveNotificationDestination(
        _guardian,
        const NotificationOpenRequest(type: 'eligibility_changed'),
      );
      final staffDestination = resolveNotificationDestination(
        _schoolStaff,
        const NotificationOpenRequest(
          type: 'eligibility_changed',
          playerId: '11',
        ),
      );

      expect(playerDestination.playerId, _player.id);
      expect(guardianDestination.kind, NotificationDestinationKind.eligibility);
      expect(staffDestination.kind, NotificationDestinationKind.inbox);
    });

    test('unknown event stays in the focused inbox', () {
      final destination = resolveNotificationDestination(
        _player,
        const NotificationOpenRequest(type: 'future_event'),
      );
      expect(destination.kind, NotificationDestinationKind.inbox);
    });

    test('FCM request matches its persisted domain event', () {
      const request = NotificationOpenRequest(
        type: 'session_scheduled',
        sessionId: '7',
      );
      final matching = AppNotification(
        id: '1',
        type: 'session_scheduled',
        title: 'Session',
        body: '',
        data: const {'sessionId': '7'},
        isRead: false,
        createdAt: DateTime.utc(2026),
      );
      final other = AppNotification(
        id: '2',
        type: 'session_scheduled',
        title: 'Other session',
        body: '',
        data: const {'sessionId': '8'},
        isRead: false,
        createdAt: DateTime.utc(2026),
      );

      expect(request.matches(matching), isTrue);
      expect(request.matches(other), isFalse);
    });
  });

  group('notification navigation controller', () {
    test('resolves profile, marks read, and supplies destination', () async {
      NotificationOpenRequest? marked;
      ResolvedNotificationNavigation? resolved;
      final controller = NotificationNavigationController(
        () async => _player,
        (request) async => marked = request,
      );
      const request = NotificationOpenRequest(
        type: 'assessment_saved',
        playerId: '11',
      );

      final opened = await controller.open(request, (value) async {
        resolved = value;
      });
      await Future<void>.delayed(Duration.zero);

      expect(opened, isTrue);
      expect(marked, same(request));
      expect(
        resolved?.destination.kind,
        NotificationDestinationKind.playerProfile,
      );
      expect(resolved?.profile, same(_player));
    });

    test('suppresses a duplicate while its route is active', () async {
      final routeClosed = Completer<void>();
      final routeOpened = Completer<void>();
      final controller = NotificationNavigationController(
        () async => _player,
        (_) async {},
      );
      const request = NotificationOpenRequest(
        type: 'session_updated',
        sourceMessageId: 'fcm-1',
      );

      final first = controller.open(request, (_) {
        routeOpened.complete();
        return routeClosed.future;
      });
      await routeOpened.future;
      final duplicate = await controller.open(request, (_) async {});
      routeClosed.complete();

      expect(duplicate, isFalse);
      expect(await first, isTrue);
    });

    test('missing profile safely falls back to the inbox', () async {
      ResolvedNotificationNavigation? resolved;
      final controller = NotificationNavigationController(
        () async => null,
        (_) async {},
      );

      await controller.open(
        const NotificationOpenRequest(type: 'session_updated'),
        (value) async => resolved = value,
      );

      expect(resolved?.profile, isNull);
      expect(resolved?.destination.kind, NotificationDestinationKind.inbox);
    });
  });

  testWidgets('PortalShell honors and updates its requested initial tab', (
    tester,
  ) async {
    Widget app(int initialIndex) => MaterialApp(
      home: PortalShell(
        initialIndex: initialIndex,
        pages: const [Text('zero'), Text('one'), Text('two')],
        navigationBarBuilder: (selected, onSelected) => NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: onSelected,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.looks_one), label: 'Zero'),
            NavigationDestination(icon: Icon(Icons.looks_two), label: 'One'),
            NavigationDestination(icon: Icon(Icons.looks_3), label: 'Two'),
          ],
        ),
      ),
    );

    await tester.pumpWidget(app(2));
    await tester.pumpAndSettle();
    expect(find.text('two'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );

    await tester.pumpWidget(app(1));
    await tester.pumpAndSettle();
    expect(find.text('one'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
  });
}
