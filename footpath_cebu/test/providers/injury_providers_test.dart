import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/data/repositories/mock_injury_repository.dart';
import 'package:footpath_cebu/domain/entities/injury_record.dart';
import 'package:footpath_cebu/domain/repositories/injury_repository.dart';
import 'package:footpath_cebu/presentation/providers/injury_providers.dart';

/// Fake repository that can be told to fail, so the controller's error paths
/// are exercised without a backend.
class _FailingInjuryRepo implements InjuryRepository {
  @override
  Future<List<InjuryRecord>> fetchInjuriesForPlayer(
    String playerId, {
    String? unlockToken,
  }) async => throw InjuryRepositoryException('boom');

  @override
  Future<InjuryRecord> saveInjury(InjuryRecord record) async =>
      throw InjuryRepositoryException('boom');

  @override
  Future<void> deleteInjury(String injuryId) async =>
      throw InjuryRepositoryException('boom');
}

InjuryRecord _draft({String? id}) => InjuryRecord(
  id: id,
  playerId: 'p1',
  description: 'Hamstring strain',
  status: InjuryStatus.active,
  occurredOn: DateTime(2026, 7, 10),
);

void main() {
  ProviderContainer containerWith(InjuryRepository repo) {
    final container = ProviderContainer(
      overrides: [injuryRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('injuriesProvider', () {
    test('returns the seeded history, most recent first', () async {
      final container = containerWith(MockInjuryRepository());

      final records = await container.read(injuriesProvider('p1').future);
      expect(records, hasLength(2));
      expect(records.first.occurredOn.isAfter(records.last.occurredOn), isTrue);
    });

    test('another player sees an empty history', () async {
      final container = containerWith(MockInjuryRepository());
      expect(await container.read(injuriesProvider('p2').future), isEmpty);
    });
  });

  group('InjuryFormController', () {
    test('submit creates a record and refreshes the list', () async {
      final container = containerWith(MockInjuryRepository());
      final sub = container.listen(injuryFormControllerProvider, (_, _) {});

      final saved = await container
          .read(injuryFormControllerProvider.notifier)
          .submit(_draft());

      expect(saved, isNotNull);
      expect(saved!.id, isNotNull); // the repository assigned an id
      expect(sub.read().hasError, isFalse);

      final records = await container.read(injuriesProvider('p1').future);
      expect(records, hasLength(3));
    });

    test('submit updates an existing record in place', () async {
      final repo = MockInjuryRepository();
      final container = containerWith(repo);
      container.listen(injuryFormControllerProvider, (_, _) {});
      final existing = (await repo.fetchInjuriesForPlayer('p1')).first;

      final saved = await container
          .read(injuryFormControllerProvider.notifier)
          .submit(existing.copyWith(status: InjuryStatus.recovered));

      expect(saved!.status, InjuryStatus.recovered);
      final records = await container.read(injuriesProvider('p1').future);
      expect(records, hasLength(2)); // replaced, not duplicated
      expect(
        records.firstWhere((r) => r.id == existing.id).status,
        InjuryStatus.recovered,
      );
    });

    test('remove deletes and reports success', () async {
      final repo = MockInjuryRepository();
      final container = containerWith(repo);
      container.listen(injuryFormControllerProvider, (_, _) {});
      final existing = (await repo.fetchInjuriesForPlayer('p1')).first;

      final ok = await container
          .read(injuryFormControllerProvider.notifier)
          .remove(existing);

      expect(ok, isTrue);
      final records = await container.read(injuriesProvider('p1').future);
      expect(records, hasLength(1));
    });

    test('failures surface as error state, not throws', () async {
      final container = containerWith(_FailingInjuryRepo());
      final sub = container.listen(injuryFormControllerProvider, (_, _) {});
      final controller = container.read(injuryFormControllerProvider.notifier);

      expect(await controller.submit(_draft()), isNull);
      expect(sub.read().hasError, isTrue);

      expect(await controller.remove(_draft(id: 'i1')), isFalse);
      expect(sub.read().hasError, isTrue);
    });
  });
}
