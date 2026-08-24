import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/data/repositories/firebase_auth_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ApiIdentity _identity() => ApiIdentity(
  uid: 'firebase-user-1',
  getIdToken: (_) async => 'firebase-id-token',
);

void main() {
  test(
    'loads the typed current profile through the authenticated client',
    () async {
      final client = AuthenticatedApiClient(
        identityProvider: _identity,
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/auth/me/');
          expect(request.headers['authorization'], 'Bearer firebase-id-token');
          return http.Response(
            jsonEncode({
              'id': 7,
              'email': 'coach@example.com',
              'first_name': 'Coach',
              'last_name': 'One',
              'role': 'COACH',
              'role_display': 'Coach',
              'photo_url': 'https://storage.example/coach.jpg',
            }),
            200,
          );
        }),
      );

      final profile = await FirebaseProfileApi(
        api: client,
      ).fetchCurrentProfile();

      expect(profile.id, '7');
      expect(profile.email, 'coach@example.com');
      expect(profile.role, 'COACH');
      expect(profile.photoUrl, 'https://storage.example/coach.jpg');
    },
  );

  test(
    'never restores authentication from an offline cached profile',
    () async {
      var calls = 0;
      final client = AuthenticatedApiClient(
        identityProvider: _identity,
        httpClient: MockClient((_) async {
          calls += 1;
          if (calls > 1) throw http.ClientException('offline');
          return http.Response(
            jsonEncode({
              'id': 7,
              'email': 'coach@example.com',
              'first_name': 'Coach',
              'last_name': 'One',
              'role': 'COACH',
              'role_display': 'Coach',
            }),
            200,
          );
        }),
      );
      final profileApi = FirebaseProfileApi(api: client);

      await profileApi.fetchCurrentProfile();
      await expectLater(
        profileApi.fetchCurrentProfile(),
        throwsA(isA<ApiNetworkException>()),
      );
    },
  );

  test('maps a malformed profile to the shared decode exception', () async {
    final client = AuthenticatedApiClient(
      identityProvider: _identity,
      httpClient: MockClient((_) async => http.Response('[]', 200)),
    );

    await expectLater(
      FirebaseProfileApi(api: client).fetchCurrentProfile(),
      throwsA(isA<ApiDecodeException>()),
    );
  });
}
