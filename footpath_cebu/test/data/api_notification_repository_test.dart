import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/data/repositories/api_notification_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('loads notifications and unread count from the API contract', () async {
    final requestedPaths = <String>[];
    final api = AuthenticatedApiClient(
      identityProvider: () =>
          ApiIdentity(uid: 'user-1', getIdToken: (_) async => 'id-token'),
      httpClient: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer id-token');
        requestedPaths.add(request.url.path);
        if (request.url.path.endsWith('/unread-count/')) {
          return http.Response(jsonEncode({'unreadCount': 1}), 200);
        }
        return http.Response(
          jsonEncode([
            {
              'id': 'n1',
              'type': 'assessment_saved',
              'title': 'Assessment updated',
              'body': 'Open the app to review it.',
              'data': {'playerId': '3'},
              'isRead': false,
              'createdAt': '2026-08-19T08:30:00Z',
            },
          ]),
          200,
        );
      }),
    );
    final repository = ApiNotificationRepository(api: api);

    final notifications = await repository.fetchNotifications();
    final unread = await repository.fetchUnreadCount();

    expect(notifications.single.id, 'n1');
    expect(unread, 1);
    expect(
      requestedPaths,
      containsAll(['/api/notifications/', '/api/notifications/unread-count/']),
    );
  });

  test('uses the read endpoints', () async {
    final requests = <http.Request>[];
    final api = AuthenticatedApiClient(
      identityProvider: () =>
          ApiIdentity(uid: 'user-1', getIdToken: (_) async => 'id-token'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('', 204);
      }),
    );
    final repository = ApiNotificationRepository(api: api);

    await repository.markRead('n1');
    await repository.markAllRead();

    expect(requests[0].method, 'PATCH');
    expect(requests[0].url.path, '/api/notifications/n1/read/');
    expect(requests[1].method, 'POST');
    expect(requests[1].url.path, '/api/notifications/read-all/');
  });
}
