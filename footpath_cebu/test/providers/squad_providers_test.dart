import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';
import 'package:footpath_cebu/presentation/providers/error_text.dart';
import 'package:footpath_cebu/presentation/providers/squad_providers.dart';

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

  @override
  Future<Player> saveAssessment(
    String playerId,
    PlayerRatings ratings, {
    required String coachNotes,
  }) async =>
      _players
          .firstWhere((p) => p.id == playerId)
          .copyWith(ratings: ratings, coachNotes: coachNotes);

  @override
  Future<Player> savePosition(String playerId, PlayerPosition position) async =>
      _players.firstWhere((p) => p.id == playerId).copyWith(position: position);
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

  @override
  Future<Player> saveAssessment(
    String playerId,
    PlayerRatings ratings, {
    required String coachNotes,
  }) async =>
      throw PlayerRepositoryException('boom');

  @override
  Future<Player> savePosition(String playerId, PlayerPosition position) async =>
      throw PlayerRepositoryException('boom');
}

Player _player(
  String id,
  String name,
  PlayerPosition position, {
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

/// A fresh container per test, with the player repository overridden — the
/// Riverpod equivalent of constructing a ViewModel with a fake. Automatic
/// retry is disabled so error-path tests fail once instead of backing off.
ProviderContainer _container(PlayerRepository repo) {
  final container = ProviderContainer(
    overrides: [playerRepositoryProvider.overrideWithValue(repo)],
    retry: (retryCount, error) => null,
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('squadProvider + filteredSquadProvider', () {
    test('loading the squad populates the filtered roster', () async {
      final container = _container(_FakePlayerRepository([
        _player('1', 'Messi', PlayerPosition.attackingMidfielder),
        _player('2', 'Ronaldo', PlayerPosition.striker),
      ]));
      final filtered = container.listen(filteredSquadProvider, (_, _) {});

      expect(filtered.read().isLoading, isTrue);
      final squad = await container.read(squadProvider.future);

      expect(squad.length, 2);
      expect(filtered.read().value!.length, 2);
    });

    test('search filters by name (case-insensitive)', () async {
      final container = _container(_FakePlayerRepository([
        _player('1', 'Messi', PlayerPosition.attackingMidfielder),
        _player('2', 'Ronaldo', PlayerPosition.striker),
      ]));
      final filtered = container.listen(filteredSquadProvider, (_, _) {});
      await container.read(squadProvider.future);

      container.read(rosterFilterProvider.notifier).search('mes');

      expect(filtered.read().value!.single.name, 'Messi');
      // The unfiltered squad is unaffected by the filter.
      expect(container.read(squadProvider).value!.length, 2);
    });

    test('search matches position too', () async {
      final container = _container(_FakePlayerRepository([
        _player('1', 'Messi', PlayerPosition.attackingMidfielder),
        _player('2', 'Ronaldo', PlayerPosition.striker),
      ]));
      final filtered = container.listen(filteredSquadProvider, (_, _) {});
      await container.read(squadProvider.future);

      container.read(rosterFilterProvider.notifier).search('st');
      expect(filtered.read().value!.single.name, 'Ronaldo');
    });

    test('clearing the query restores the full roster', () async {
      final container =
          _container(_FakePlayerRepository([_player('1', 'Messi', PlayerPosition.attackingMidfielder)]));
      final filtered = container.listen(filteredSquadProvider, (_, _) {});
      await container.read(squadProvider.future);

      container.read(rosterFilterProvider.notifier).search('nobody');
      expect(filtered.read().value, isEmpty);
      container.read(rosterFilterProvider.notifier).search('');
      expect(filtered.read().value!.length, 1);
    });

    test('a repository error surfaces with its message', () async {
      final container = _container(_FailingPlayerRepository());
      final filtered = container.listen(filteredSquadProvider, (_, _) {});

      await expectLater(
        container.read(squadProvider.future),
        throwsA(anything),
      );

      final state = filtered.read();
      expect(state.hasError, isTrue);
      expect(friendlyErrorMessage(state.error, 'fallback'), 'boom');
    });

    test('filterByTier narrows the roster to that tier only', () async {
      final container = _container(_FakePlayerRepository([
        _player('1', 'Messi', PlayerPosition.attackingMidfielder, tier: AgeTier.development),
        _player('2', 'Ronaldo', PlayerPosition.striker, tier: AgeTier.pathway),
        _player('3', 'Yamal', PlayerPosition.rightWinger, tier: AgeTier.foundation),
        _player('4', 'Pedri', PlayerPosition.centralMidfielder, tier: AgeTier.foundation),
      ]));
      final filtered = container.listen(filteredSquadProvider, (_, _) {});
      await container.read(squadProvider.future);
      final notifier = container.read(rosterFilterProvider.notifier);

      notifier.filterByTier(AgeTier.foundation);
      expect(filtered.read().value!.map((p) => p.name), ['Yamal', 'Pedri']);

      notifier.filterByTier(AgeTier.pathway);
      expect(filtered.read().value!.map((p) => p.name), ['Ronaldo']);
    });

    test('filterByTier(null) restores the whole squad', () async {
      final container = _container(_FakePlayerRepository([
        _player('1', 'Messi', PlayerPosition.attackingMidfielder, tier: AgeTier.development),
        _player('2', 'Yamal', PlayerPosition.rightWinger, tier: AgeTier.foundation),
      ]));
      final filtered = container.listen(filteredSquadProvider, (_, _) {});
      await container.read(squadProvider.future);
      final notifier = container.read(rosterFilterProvider.notifier);

      notifier.filterByTier(AgeTier.foundation);
      expect(filtered.read().value!.length, 1);
      notifier.filterByTier(null);
      expect(filtered.read().value!.length, 2);
    });

    test('tier filter and search narrow together', () async {
      final container = _container(_FakePlayerRepository([
        _player('1', 'Messi', PlayerPosition.attackingMidfielder, tier: AgeTier.foundation),
        _player('2', 'Mbappe', PlayerPosition.striker, tier: AgeTier.pathway),
        _player('3', 'Yamal', PlayerPosition.rightWinger, tier: AgeTier.foundation),
      ]));
      final filtered = container.listen(filteredSquadProvider, (_, _) {});
      await container.read(squadProvider.future);
      final notifier = container.read(rosterFilterProvider.notifier);

      notifier.filterByTier(AgeTier.foundation);

      // Mbappe matches the query but is excluded by the tier filter.
      notifier.search('m');
      expect(filtered.read().value!.map((p) => p.name), ['Messi', 'Yamal']);

      // Messi is in the tier but is excluded by the query.
      notifier.search('yam');
      expect(filtered.read().value!.map((p) => p.name), ['Yamal']);
    });
  });
}
