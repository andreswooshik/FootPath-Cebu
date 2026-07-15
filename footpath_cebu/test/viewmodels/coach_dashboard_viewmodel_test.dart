import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
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

Player _player(
  String id,
  String name,
  String position, {
  AgeTier tier = AgeTier.development,
}) =>
    Player(
      id: id,
      name: name,
      age: 15,
      classYear: 'Class of 2026',
      ageTier: tier,
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

    test('filterByTier narrows the roster to that tier only', () async {
      final vm = CoachDashboardViewModel(
        GetSquad(_FakePlayerRepository([
          _player('1', 'Messi', 'CAM', tier: AgeTier.development),
          _player('2', 'Ronaldo', 'ST', tier: AgeTier.pathway),
          _player('3', 'Yamal', 'RW', tier: AgeTier.foundation),
          _player('4', 'Pedri', 'CM', tier: AgeTier.foundation),
        ])),
      );
      await vm.loadSquad();

      vm.filterByTier(AgeTier.foundation);
      expect(vm.players.map((p) => p.name), ['Yamal', 'Pedri']);

      vm.filterByTier(AgeTier.pathway);
      expect(vm.players.map((p) => p.name), ['Ronaldo']);
    });

    test('filterByTier(null) restores the whole squad', () async {
      final vm = CoachDashboardViewModel(
        GetSquad(_FakePlayerRepository([
          _player('1', 'Messi', 'CAM', tier: AgeTier.development),
          _player('2', 'Yamal', 'RW', tier: AgeTier.foundation),
        ])),
      );
      await vm.loadSquad();

      vm.filterByTier(AgeTier.foundation);
      expect(vm.players.length, 1);
      vm.filterByTier(null);
      expect(vm.players.length, 2);
    });

    test('tier filter and search narrow together', () async {
      final vm = CoachDashboardViewModel(
        GetSquad(_FakePlayerRepository([
          _player('1', 'Messi', 'CAM', tier: AgeTier.foundation),
          _player('2', 'Mbappe', 'ST', tier: AgeTier.pathway),
          _player('3', 'Yamal', 'RW', tier: AgeTier.foundation),
        ])),
      );
      await vm.loadSquad();

      vm.filterByTier(AgeTier.foundation);

      // Mbappe matches the query but is excluded by the tier filter.
      vm.search('m');
      expect(vm.players.map((p) => p.name), ['Messi', 'Yamal']);

      // Messi is in the tier but is excluded by the query.
      vm.search('yam');
      expect(vm.players.map((p) => p.name), ['Yamal']);
    });

    test('countFor counts a tier regardless of the active search', () async {
      final vm = CoachDashboardViewModel(
        GetSquad(_FakePlayerRepository([
          _player('1', 'Messi', 'CAM', tier: AgeTier.foundation),
          _player('2', 'Yamal', 'RW', tier: AgeTier.foundation),
          _player('3', 'Mbappe', 'ST', tier: AgeTier.pathway),
        ])),
      );
      await vm.loadSquad();
      vm.search('zzzz');

      expect(vm.countFor(AgeTier.foundation), 2);
      expect(vm.countFor(AgeTier.pathway), 1);
      expect(vm.countFor(AgeTier.development), 0);
      // ...while the header still reports the true squad size.
      expect(vm.registeredCount, 3);
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
