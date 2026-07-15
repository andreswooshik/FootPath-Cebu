import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';
import 'package:footpath_cebu/domain/usecases/get_linked_players.dart';
import 'package:footpath_cebu/domain/usecases/get_my_profile.dart';
import 'package:footpath_cebu/domain/usecases/get_player_attendance.dart';
import 'package:footpath_cebu/presentation/viewmodels/guardian_dashboard_viewmodel.dart';
import 'package:footpath_cebu/presentation/viewmodels/player_dashboard_viewmodel.dart';

Player _player(String id, String name) => Player(
  id: id,
  name: name,
  age: 15,
  classYear: 'Class of 2026',
  ageTier: 'Development',
  position: 'CM',
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
}

class _FakeAttendanceRepo implements AttendanceRepository {
  _FakeAttendanceRepo() : records = const [];
  final List<Attendance> records;

  @override
  Future<List<Attendance>> fetchAttendanceForPlayer(String playerId) async =>
      records.where((a) => a.playerId == playerId).toList();
}

void main() {
  group('PlayerDashboardViewModel', () {
    test('load populates the signed-in player', () async {
      final vm = PlayerDashboardViewModel(
        GetMyProfile(_FakeRepo(me: _player('1', 'Messi'))),
      );
      await vm.load();

      expect(vm.error, isNull);
      expect(vm.isLoading, isFalse);
      expect(vm.player?.name, 'Messi');
    });

    test('load surfaces repository errors', () async {
      final vm = PlayerDashboardViewModel(GetMyProfile(_FakeRepo()));
      await vm.load();

      expect(vm.player, isNull);
      expect(vm.error, 'no profile');
    });
  });

  group('GuardianDashboardViewModel', () {
    test('load populates linked children and count', () async {
      final vm = GuardianDashboardViewModel(
        GetLinkedPlayers(
          _FakeRepo(children: [_player('2', 'A'), _player('3', 'B')]),
        ),
        GetPlayerAttendance(_FakeAttendanceRepo()),
      );
      await vm.load();

      expect(vm.error, isNull);
      expect(vm.childCount, 2);
      expect(vm.children.map((p) => p.name), ['A', 'B']);
    });

    test('empty roster yields zero children', () async {
      final vm = GuardianDashboardViewModel(
        GetLinkedPlayers(_FakeRepo()),
        GetPlayerAttendance(_FakeAttendanceRepo()),
      );
      await vm.load();

      expect(vm.childCount, 0);
      expect(vm.children, isEmpty);
    });
  });
}
