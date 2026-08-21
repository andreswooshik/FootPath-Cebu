import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/data/repositories/api_player_repository.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';
import 'package:footpath_cebu/domain/usecases/upload_player_photo.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _pngBytes = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00];

Map<String, dynamic> _playerJson() => {
  'id': 7,
  'name': 'Ana Player',
  'age': 15,
  'classYear': 'Class of 2028',
  'ageTier': 'DEVELOPMENT',
  'ratings': <String, int>{},
  'eligibility': 'ELIGIBLE',
  'photoUrl': 'https://storage.example/7.png',
};

class _RecordingWriter implements PlayerPhotoWriter {
  var calls = 0;

  @override
  Future<Player> uploadPhoto(
    String playerId, {
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    calls += 1;
    return Player.fromJson(_playerJson());
  }
}

void main() {
  test('repository sends an authenticated typed multipart photo', () async {
    final api = AuthenticatedApiClient(
      identityProvider: () => ApiIdentity(
        uid: 'coach-uid',
        getIdToken: (_) async => 'firebase-token',
      ),
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/players/7/photo/');
        expect(request.headers['authorization'], 'Bearer firebase-token');
        expect(
          request.headers['content-type'],
          startsWith('multipart/form-data'),
        );
        final body = latin1.decode(request.bodyBytes);
        expect(body, contains('name="photo"'));
        expect(body, contains('filename="headshot.png"'));
        expect(body, contains('content-type: image/png'));
        return http.Response(jsonEncode(_playerJson()), 200);
      }),
    );
    final repository = ApiPlayerRepository(api: api);

    final player = await repository.uploadPhoto(
      '7',
      bytes: _pngBytes,
      filename: 'headshot.png',
      contentType: 'image/png',
    );

    expect(player.id, '7');
    expect(player.photoUrl, 'https://storage.example/7.png');
  });

  test('repository exposes the safe server upload error', () async {
    final api = AuthenticatedApiClient(
      identityProvider: () => ApiIdentity(
        uid: 'coach-uid',
        getIdToken: (_) async => 'firebase-token',
      ),
      httpClient: MockClient(
        (_) async =>
            http.Response('{"detail":"That player is not in your club."}', 403),
      ),
    );
    final repository = ApiPlayerRepository(api: api);

    await expectLater(
      repository.uploadPhoto(
        '7',
        bytes: _pngBytes,
        filename: 'headshot.png',
        contentType: 'image/png',
      ),
      throwsA(
        isA<PlayerRepositoryException>().having(
          (error) => error.message,
          'message',
          'That player is not in your club.',
        ),
      ),
    );
  });

  test('use case rejects oversized and unsupported files before upload', () {
    final writer = _RecordingWriter();
    final upload = UploadPlayerPhoto(writer);

    expect(
      () => upload(
        '7',
        bytes: List<int>.filled(UploadPlayerPhoto.maxBytes + 1, 0),
        filename: 'large.png',
        contentType: 'image/png',
      ),
      throwsA(isA<PlayerRepositoryException>()),
    );
    expect(
      () => upload(
        '7',
        bytes: const [1, 2, 3],
        filename: 'avatar.gif',
        contentType: 'image/gif',
      ),
      throwsA(isA<PlayerRepositoryException>()),
    );
    expect(writer.calls, 0);
  });
}
