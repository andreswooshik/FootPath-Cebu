import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/data/repositories/api_device_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('registers and unregisters the current FCM token', () async {
    final requests = <http.Request>[];
    final api = AuthenticatedApiClient(
      identityProvider: () =>
          ApiIdentity(uid: 'user-1', getIdToken: (_) async => 'id-token'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('', 204);
      }),
    );
    final repository = ApiDeviceRepository(() async => 'fcm-token', api);

    await repository.registerCurrentDevice();
    await repository.unregisterCurrentDevice();

    expect(requests.map((request) => request.method), ['POST', 'DELETE']);
    expect(
      requests.every((request) => request.url.path == '/api/devices/'),
      isTrue,
    );
    expect(jsonDecode(requests.first.body)['token'], 'fcm-token');
    expect(jsonDecode(requests.last.body), {'token': 'fcm-token'});
  });
}
