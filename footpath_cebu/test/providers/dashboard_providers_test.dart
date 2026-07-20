import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/guardian_dashboard_providers.dart';
import 'package:footpath_cebu/presentation/providers/player_dashboard_providers.dart';

Player _player(String id, String name) => Player(
  id: id,
  name: name,
  age: 15,
  classYear: 'Class of 2026',
  ageTier: AgeTier.development,
  position: PlayerPosition.centralMidfielder,
  eligibility: EligibilityStatus.eligible,
  ratings: const PlayerRatings(
    pace: 80,
    shooting: 80,
    passing: 80,
    dribbling: 80,
    defending: 80,
    physical: 80,
  ),
);

class _FakeRepo implements PlayerRepository {
  _FakeRepo({this.me, this.children = const []});
  final Player? me;
  final List<Player> children;

  @override
  Future<List<Player>> fetchSquad() async => const [];

  @override
  Future<Player> fetchMyProfile() async {
    final m = me;
    if (m == null) throw PlayerRepositoryException('no profile');
    return m;
  }

  @override
  Future<List<Player>> fetchLinkedPlayers() async => children;

  @override
  Future<Player> savePosition(String playerId, PlayerPosition position) =>
      throw UnimplementedError();

  @override
  Future<Player> saveAssessment(
    String playerId,
    PlayerRatings ratings, {
    required String coachNotes,
  }) async =>
      throw UnimplementedError();
}

class _FakeAttendanceRepo implements AttendanceRepository {
  _FakeAttendanceRepo() : records = const [];
  final List<Attendance> records;

  @override
  Future<List<Attendance>> fetchAttendanceForPlayer(String playerId) async =>
      records.where((a) => a.playerId == playerId).toList();

  // The guardian dashboard only reads a player's history — the session
  // read/write are never reached here.
  @override
  Future<List<Attendance>> fetchAttendanceForSession(String sessionId) =>
      throw UnimplementedError();

  @override
  Future<List<Attendance>> saveSessionAttendance(
    String sessionId,
    List<Attendance> records,
  ) =>
      throw UnimplementedError();
}

/// Automatic retry is disabled so error-path tests fail once instead of
/// backing off until the test times out.
ProviderContainer _container(PlayerRepository repo) {
  final container = ProviderContainer(
    overrides: [
      playerRepositoryProvider.overrideWithValue(repo),
      attendanceRepositoryProvider.overrideWithValue(_FakeAttendanceRepo()),
    ],
    retry: (retryCount, error) => null,
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('myProfileProvider', () {
    test('resolves to the signed-in player', () async {
      final container = _container(_FakeRepo(me: _player('1', 'Messi')));
      final sub = container.listen(myProfileProvider, (_, _) {});

      final player = await container.read(myProfileProvider.future);

      expect(player.name, 'Messi');
      expect(sub.read().hasError, isFalse);
    });

    test('surfaces repository errors with their message', () async {
      final container = _container(_FakeRepo());
      final sub = container.listen(myProfileProvider, (_, _) {});

      await expectLater(
        container.read(myProfileProvider.future),
        throwsA(anything),
      );

      final state = sub.read();
      expect(state.hasError, isTrue);
      expect(friendlyErrorMessage(state.error, 'fallback'), 'no profile');
    });
  });

  group('guardian providers', () {
    test('linked children load and the first is selected by default',
        () async {
      final container = _container(
        _FakeRepo(children: [_player('2', 'A'), _player('3', 'B')]),
      );
      final selected = container.listen(selectedChildProvider, (_, _) {});

      final children = await container.read(linkedPlayersProvider.future);

      expect(children.map((p) => p.name), ['A', 'B']);
      expect(selected.read()?.name, 'A');
    });

    test('selecting a child switches the derived selection', () async {
      final container = _container(
        _FakeRepo(children: [_player('2', 'A'), _player('3', 'B')]),
      );
      final selected = container.listen(selectedChildProvider, (_, _) {});
      await container.read(linkedPlayersProvider.future);

      container.read(selectedChildIdProvider.notifier).select('3');

      expect(selected.read()?.name, 'B');
    });

    test('an empty roster yields no selected child', () async {
      final container = _container(_FakeRepo());
      final selected = container.listen(selectedChildProvider, (_, _) {});

      final children = await container.read(linkedPlayersProvider.future);

      expect(children, isEmpty);
      expect(selected.read(), isNull);
    });
  });

  group('AttendanceSummary', () {
    Attendance record(AttendanceStatus status) => Attendance(
          playerId: 'p1',
          status: status,
          updatedAt: DateTime(2026, 7, 16),
        );

    test('presentPercent is 0 for no records', () {
      expect(const <Attendance>[].presentPercent, 0);
    });

    test('presentPercent rounds the present share', () {
      final records = [
        record(AttendanceStatus.present),
        record(AttendanceStatus.present),
        record(AttendanceStatus.absent),
      ];
      expect(records.presentPercent, 67);
      expect(records.sessionCount, 3);
    });

    test('recent keeps only the first three records', () {
      final records = List.generate(
        5,
        (_) => record(AttendanceStatus.present),
      );
      expect(records.recent.length, 3);
    });
  });
}
