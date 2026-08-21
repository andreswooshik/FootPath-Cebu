import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/app_notification.dart';

void main() {
  test('parses the backend notification contract', () {
    final notification = AppNotification.fromJson({
      'id': 42,
      'type': 'session_scheduled',
      'title': 'New training session',
      'body': 'Training starts tomorrow.',
      'data': {'sessionId': '7'},
      'isRead': false,
      'createdAt': '2026-08-19T08:30:00Z',
    });

    expect(notification.id, '42');
    expect(notification.type, 'session_scheduled');
    expect(notification.data['sessionId'], '7');
    expect(notification.isRead, isFalse);
    expect(notification.createdAt, DateTime.utc(2026, 8, 19, 8, 30));
  });

  test('uses safe defaults for optional malformed fields', () {
    final notification = AppNotification.fromJson({
      'id': 'n1',
      'data': 'not-a-map',
    });

    expect(notification.title, 'FootPath Cebu');
    expect(notification.data, isEmpty);
    expect(notification.isRead, isFalse);
  });
}
