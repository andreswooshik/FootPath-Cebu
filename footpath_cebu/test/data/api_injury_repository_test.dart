import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/data/network/authenticated_api_client.dart';
import 'package:footpath_cebu/data/repositories/api_injury_repository.dart';
import 'package:footpath_cebu/domain/entities/injury_record.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _injuryJson({
  String status = 'ACTIVE',
  String reviewStatus = 'PENDING',
}) => {
  'id': 'injury-1',
  'playerId': 'player-1',
  'playerName': 'Ana Santos',
  'description': 'Sprained ankle',
  'bodyPart': 'Left ankle',
  'status': status,
  'occurredOn': '2026-08-27',
  'resolvedOn': null,
  'notes': '',
  'reviewStatus': reviewStatus,
  'reporterName': 'Ana Santos',
  'reporterRole': 'PLAYER',
  'rejectionReason': '',
  'reviewedAt': null,
  'archivedAt': null,
  'pendingStatusUpdate': null,
  'canEditPending': reviewStatus == 'PENDING',
  'canReview': false,
  'canEditConfirmed': false,
  'canArchive': false,
  'canRequestStatusUpdate': reviewStatus == 'CONFIRMED',
  'createdAt': '2026-08-27T08:00:00Z',
  'updatedAt': '2026-08-27T08:00:00Z',
};

AuthenticatedApiClient _api(http.Client client) => AuthenticatedApiClient(
  identityProvider: () =>
      ApiIdentity(uid: 'user-1', getIdToken: (_) async => 'id-token'),
  httpClient: client,
);

void main() {
  test(
    'submits a targeted Pending report with the player unlock token',
    () async {
      late http.Request captured;
      final repository = ApiInjuryRepository(
        api: _api(
          MockClient((request) async {
            captured = request;
            return http.Response(jsonEncode(_injuryJson()), 201);
          }),
        ),
        unlockTokenFor: (playerId) => 'unlock-$playerId',
      );
      final draft = InjuryRecord(
        playerId: 'player-1',
        description: 'Sprained ankle',
        bodyPart: 'Left ankle',
        status: InjuryStatus.active,
        occurredOn: DateTime(2026, 8, 27),
      );

      final saved = await repository.saveInjury(draft);

      expect(captured.method, 'POST');
      expect(captured.url.path, '/api/injuries/');
      expect(captured.headers['X-Player-Unlock'], 'unlock-player-1');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['playerId'], 'player-1');
      expect(body['status'], 'ACTIVE');
      expect(saved.reviewStatus, InjuryReportStatus.pending);
    },
  );

  test(
    'uses dedicated recovery request and Coordinator review endpoints',
    () async {
      final captured = <http.Request>[];
      final repository = ApiInjuryRepository(
        api: _api(
          MockClient((request) async {
            captured.add(request);
            if (request.url.path.endsWith('/status-updates/')) {
              return http.Response(
                jsonEncode({
                  'id': 'update-1',
                  'proposedStatus': 'RECOVERING',
                  'proposedResolvedOn': null,
                  'notes': 'Light training started.',
                  'reviewStatus': 'PENDING',
                  'submittedByName': 'Ana Santos',
                  'submittedByRole': 'PLAYER',
                  'rejectionReason': '',
                  'createdAt': '2026-08-28T08:00:00Z',
                }),
                201,
              );
            }
            return http.Response(
              jsonEncode(
                _injuryJson(status: 'RECOVERING', reviewStatus: 'CONFIRMED'),
              ),
              200,
            );
          }),
        ),
        unlockTokenFor: (playerId) => 'unlock-$playerId',
      );
      final injury = InjuryRecord(
        id: 'injury-1',
        playerId: 'player-1',
        description: 'Sprained ankle',
        status: InjuryStatus.active,
        occurredOn: DateTime(2026, 8, 27),
        reviewStatus: InjuryReportStatus.confirmed,
      );

      final update = await repository.requestStatusUpdate(
        injury,
        const InjuryStatusUpdateDraft(
          proposedStatus: InjuryStatus.recovering,
          notes: 'Light training started.',
        ),
      );
      final reviewed = await repository.reviewStatusUpdate(
        'injury-1',
        update.id,
        approve: true,
      );

      expect(captured[0].url.path, '/api/injuries/injury-1/status-updates/');
      expect(captured[0].headers['X-Player-Unlock'], 'unlock-player-1');
      expect(
        (jsonDecode(captured[0].body)
            as Map<String, dynamic>)['proposedStatus'],
        'RECOVERING',
      );
      expect(
        captured[1].url.path,
        '/api/injuries/injury-1/status-updates/update-1/review/',
      );
      expect(
        (jsonDecode(captured[1].body) as Map<String, dynamic>)['action'],
        'APPROVE',
      );
      expect(reviewed.status, InjuryStatus.recovering);
    },
  );
}
