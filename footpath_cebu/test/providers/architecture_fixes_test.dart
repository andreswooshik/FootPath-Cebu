import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/core/di/registration_dependencies.dart';
import 'package:footpath_cebu/data/repositories/mock_player_stats_repository.dart';
import 'package:footpath_cebu/domain/entities/coordinator_person.dart';
import 'package:footpath_cebu/domain/entities/player_stats.dart';
import 'package:footpath_cebu/domain/repositories/coordinator_people_repository.dart';
import 'package:footpath_cebu/presentation/providers/coordinator_people_providers.dart';
import 'package:footpath_cebu/presentation/providers/player_stats_providers.dart';

class _StatsRepository extends MockPlayerStatsRepository {
  int reads = 0;
  bool fail = false;

  @override
  Future<PlayerStats> fetchStats(String id, {bool forceRefresh = false}) {
    reads++;
    return super.fetchStats(id);
  }

  @override
  Future<PlayerStatsSaveResult> saveAssessment(
    String id,
    PlayerStatsDraft draft,
  ) {
    if (fail) throw StateError('Save failed');
    return super
        .fetchStats(id)
        .then(
          (stats) => PlayerStatsSaveResult(
            assessment: stats.latest!,
            comparison: stats.comparison,
          ),
        );
  }
}

class _PeopleRepository implements CoordinatorPeopleRepository {
  int deletes = 0;
  bool fail = false;

  @override
  Future<void> deletePerson(CoordinatorPersonRole role, String id) async {
    deletes++;
    if (fail) throw StateError('Delete failed');
  }

  @override
  Future<CoordinatorPersonDetails> fetchDetails(
    CoordinatorPersonRole role,
    String id,
  ) => throw UnimplementedError();
}

void main() {
  test('mock runtime selects Player Stats without a live API', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(playerStatsRepositoryProvider),
      isA<MockPlayerStatsRepository>(),
    );
    expect(
      (await container.read(
        playerStatsProvider('p1').future,
      )).catalog.attributes,
      isNotEmpty,
    );
  });

  test('player capabilities share one statically typed adapter', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final source = container.read(playerDataSourceProvider);
    expect(container.read(playerRepositoryProvider), same(source));
    expect(container.read(playerDetailsReaderProvider), same(source));
    expect(container.read(playerPhotoWriterProvider), same(source));
    expect(
      container.read(developmentAssessmentRepositoryProvider),
      same(source),
    );
  });

  test(
    'stats save refreshes once, while failed saves retain the read state',
    () async {
      final repo = _StatsRepository();
      final container = ProviderContainer(
        overrides: [playerStatsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final stats = container.listen(playerStatsProvider('p1'), (_, _) {});
      final mutation = container.listen(
        playerStatsControllerProvider('p1'),
        (_, _) {},
      );
      addTearDown(stats.close);
      addTearDown(mutation.close);
      await container.read(playerStatsProvider('p1').future);
      final controller = container.read(
        playerStatsControllerProvider('p1').notifier,
      );
      const draft = PlayerStatsDraft(
        catalogVersion: 1,
        scores: {'pace': 81},
        reason: 'MONTHLY_REVIEW',
        coachNotes: 'Progress',
      );
      expect(await controller.save('p1', draft), isNotNull);
      await container.read(playerStatsProvider('p1').future);
      expect(repo.reads, 2);
      repo.fail = true;
      expect(await controller.save('p1', draft), isNull);
      expect(
        container.read(playerStatsControllerProvider('p1')).hasError,
        isTrue,
      );
      expect(repo.reads, 2);
    },
  );

  test('person deletion exposes errors and supports retry', () async {
    final repo = _PeopleRepository()..fail = true;
    final container = ProviderContainer(
      overrides: [coordinatorPeopleRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    const key = CoordinatorPersonKey(CoordinatorPersonRole.player, 'p1');
    final subscription = container.listen(
      coordinatorPersonControllerProvider(key),
      (_, _) {},
    );
    addTearDown(subscription.close);
    final controller = container.read(
      coordinatorPersonControllerProvider(key).notifier,
    );
    expect(await controller.delete(key), isFalse);
    expect(
      container.read(coordinatorPersonControllerProvider(key)).hasError,
      isTrue,
    );
    repo.fail = false;
    expect(await controller.delete(key), isTrue);
    expect(repo.deletes, 2);
    expect(
      container.read(coordinatorPersonControllerProvider(key)).hasError,
      isFalse,
    );
  });
}
