import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/data/repositories/api_profile_photo_repository.dart';
import 'package:footpath_cebu/domain/entities/user_profile.dart';
import 'package:footpath_cebu/domain/repositories/profile_photo_repository.dart';
import 'package:footpath_cebu/domain/usecases/upload_profile_photo.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _profile = UserProfile(
  id: '7',
  email: 'coach@example.com',
  firstName: 'Coach',
  lastName: 'One',
  role: 'COACH',
  roleDisplay: 'Coach',
);

const _pngBytes = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

class _RecordingRepository implements ProfilePhotoRepository {
  var calls = 0;

  @override
  Future<UserProfile> uploadMyPhoto(
    UserProfile profile, {
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    calls += 1;
    return profile;
  }
}

void main() {
  test(
    'coach profile repository uploads to the authenticated Django API',
    () async {
      final api = AuthenticatedApiClient(
        identityProvider: () => ApiIdentity(
          uid: 'coach-uid',
          getIdToken: (_) async => 'firebase-token',
        ),
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/auth/me/photo/');
          expect(request.headers['authorization'], 'Bearer firebase-token');
          final body = latin1.decode(request.bodyBytes);
          expect(body, contains('name="photo"'));
          expect(body, contains('filename="coach.png"'));
          return http.Response(
            jsonEncode({
              'id': 7,
              'email': 'coach@example.com',
              'first_name': 'Coach',
              'last_name': 'One',
              'role': 'COACH',
              'role_display': 'Coach',
              'photo_url': 'https://storage.example/coach.png',
            }),
            200,
          );
        }),
      );

      final updated = await ApiProfilePhotoRepository(api: api).uploadMyPhoto(
        _profile,
        bytes: _pngBytes,
        filename: 'coach.png',
        contentType: 'image/png',
      );

      expect(updated.photoUrl, 'https://storage.example/coach.png');
    },
  );

  test('profile photo use case validates before calling the repository', () {
    final repository = _RecordingRepository();
    final upload = UploadProfilePhoto(repository);

    expect(
      () => upload(
        _profile,
        bytes: const [1],
        filename: 'coach.gif',
        contentType: 'image/gif',
      ),
      throwsA(isA<ProfilePhotoRepositoryException>()),
    );
    expect(repository.calls, 0);
  });
}
