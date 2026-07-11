import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';
import 'package:footpath_cebu/domain/usecases/get_squad.dart';
import 'package:footpath_cebu/presentation/viewmodels/coach_dashboard_viewmodel.dart';

/// Fake repo returning a fixed roster — lets us assert on filtering/counts
/// without touching Firebase or HTTP.
class _FakePlayerRepository implements PlayerRepository {
  _FakePlayerRepository(this._players);
  final List<Player> _players;

  @override
  Future<List<Player>> fetchSquad() async => _players;

  @override
  Future<Player> fetchMyProfile() async => _players.first;

  @override
  Future<List<Player>> fetchLinkedPlayers() async => _players;
}

/// Fake repo that always fails, to exercise the error path.
class _FailingPlayerRepository implements PlayerRepository {
  @override
  Future<List<Player>> fetchSquad() async =>
      throw PlayerRepositoryException('boom');

  @override
  Future<Player> fetchMyProfile() async =>
      throw PlayerRepositoryException('boom');

  @override
  Future<List<Player>> fetchLinkedPlayers() async =>
      throw PlayerRepositoryException('boom');
}

Player _player(String id, String name, String position) => Player(
      id: id,
      name: name,
      age: 15,
      classYear: 'Class of 2026',
      ageTier: 'Development',
      position: position,
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

void main() {
  group('CoachDashboardViewModel', () {
    test('loadSquad populates players and registered count', () async {
      final vm = CoachDashboardViewModel(
        GetSquad(_FakePlayerRepository([
          _player('1', 'Messi', 'CAM'),
          _player('2', 'Ronaldo', 'ST'),
        ])),
      );

      expect(vm.isLoading, isFalse);
      await vm.loadSquad();

      expect(vm.isLoading, isFalse);
      expect(vm.error, isNull);
      expect(vm.registeredCount, 2);
      expect(vm.players.length, 2);
    });

    test('search filters by name (case-insensitive)', () async {
      final vm = CoachDashboardViewModel(
        GetSquad(_FakePlayerRepository([
          _player('1', 'Messi', 'CAM'),
          _player('2', 'Ronaldo', 'ST'),
        ])),
      );
      await vm.loadSquad();

      vm.search('mes');
      expect(vm.players.length, 1);
      expect(vm.players.single.name, 'Messi');
      // Count is unaffected by the filter.
      expect(vm.registeredCount, 2);
    });

    test('search matches position too', () async {
      final vm = CoachDashboardViewModel(
        GetSquad(_FakePlayerRepository([
          _player('1', 'Messi', 'CAM'),
          _player('2', 'Ronaldo', 'ST'),
        ])),
      );
      await vm.loadSquad();

      vm.search('st');
      expect(vm.players.single.name, 'Ronaldo');
    });

    test('clearing the query restores the full roster', () async {
      final vm = CoachDashboardViewModel(
        GetSquad(_FakePlayerRepository([_player('1', 'Messi', 'CAM')])),
      );
      await vm.loadSquad();

      vm.search('nobody');
      expect(vm.players, isEmpty);
      vm.search('');
      expect(vm.players.length, 1);
    });

    test('loadSquad surfaces repository errors', () async {
      final vm = CoachDashboardViewModel(GetSquad(_FailingPlayerRepository()));
      await vm.loadSquad();

      expect(vm.error, 'boom');
      expect(vm.players, isEmpty);
      expect(vm.isLoading, isFalse);
    });

    test('notifies listeners when loading and searching', () async {
      final vm = CoachDashboardViewModel(
        GetSquad(_FakePlayerRepository([_player('1', 'Messi', 'CAM')])),
      );
      var notifications = 0;
      vm.addListener(() => notifications++);

      await vm.loadSquad(); // start + finish => at least 2
      vm.search('m'); // => at least 1 more
      expect(notifications, greaterThanOrEqualTo(3));
    });
  });
}
