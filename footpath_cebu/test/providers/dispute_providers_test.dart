import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/data/repositories/mock_dispute_repository.dart';
import 'package:footpath_cebu/domain/entities/dispute.dart';
import 'package:footpath_cebu/domain/entities/page_slice.dart';
import 'package:footpath_cebu/domain/repositories/dispute_repository.dart';
import 'package:footpath_cebu/presentation/providers/dispute_providers.dart';

class _FailingDisputeRepo implements DisputeRepository {
  @override
  Future<Dispute> fetchDispute(String disputeId) async =>
      throw DisputeRepositoryException('Could not load dispute.');
  @override
  Future<List<Dispute>> fetchDisputes() async =>
      throw DisputeRepositoryException('boom');

  @override
  Future<PageSlice<Dispute>> fetchDisputePage({
    required int offset,
    required int limit,
  }) async => throw DisputeRepositoryException('boom');

  @override
  Future<Dispute> raiseDispute({
    required DisputeCategory category,
    required String summary,
    String? detail,
    String? subjectPlayerId,
  }) async => throw DisputeRepositoryException('boom');

  @override
  Future<Dispute> respondToDispute(
    String disputeId,
    String body, {
    DisputeStatus? statusChangeTo,
  }) async => throw DisputeRepositoryException('boom');
}

class _PagedDisputeRepo extends MockDisputeRepository {
  final requestedOffsets = <int>[];

  @override
  Future<PageSlice<Dispute>> fetchDisputePage({
    required int offset,
    required int limit,
  }) async {
    requestedOffsets.add(offset);
    final dispute = Dispute(
      id: 'd$offset',
      category: DisputeCategory.attendance,
      status: DisputeStatus.open,
      summary: 'Page $offset',
      createdAt: DateTime(2026, 9, 10),
      updatedAt: DateTime(2026, 9, 10),
    );
    return PageSlice(items: [dispute], nextOffset: offset == 0 ? limit : null);
  }
}

void main() {
  ProviderContainer containerWith(DisputeRepository repo) {
    final container = ProviderContainer(
      overrides: [disputeRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('disputesProvider returns the seeded dispute with its thread', () async {
    final container = containerWith(MockDisputeRepository());

    final result = await container.read(disputesProvider.future);
    expect(result.items, hasLength(1));
    expect(result.items.single.status, DisputeStatus.underReview);
    expect(result.items.single.responses, hasLength(1));
  });

  test('loads later dispute pages only when requested', () async {
    final repo = _PagedDisputeRepo();
    final container = containerWith(repo);
    final subscription = container.listen(disputesProvider, (_, _) {});
    addTearDown(subscription.close);

    final first = await container.read(disputesProvider.future);
    expect(first.items.single.summary, 'Page 0');
    expect(first.hasMore, isTrue);
    expect(repo.requestedOffsets, [0]);

    await container.read(disputesProvider.notifier).loadMore();
    final loaded = container.read(disputesProvider).requireValue;
    expect(loaded.items.map((item) => item.summary), ['Page 0', 'Page 50']);
    expect(loaded.hasMore, isFalse);
    expect(repo.requestedOffsets, [0, 50]);
  });

  test('raise creates an OPEN dispute and refreshes the list', () async {
    final container = containerWith(MockDisputeRepository());
    container.listen(disputeFormControllerProvider, (_, _) {});

    final dispute = await container
        .read(disputeFormControllerProvider.notifier)
        .raise(
          category: DisputeCategory.assessment,
          summary: 'Rating query',
          subjectPlayerId: 'p2',
        );

    expect(dispute, isNotNull);
    expect(dispute!.status, DisputeStatus.open);
    final result = await container.read(disputesProvider.future);
    expect(result.items, hasLength(2));
  });

  test('respond appends to the thread and applies a status change', () async {
    final repo = MockDisputeRepository();
    final container = containerWith(repo);
    container.listen(disputeFormControllerProvider, (_, _) {});

    final updated = await container
        .read(disputeFormControllerProvider.notifier)
        .respond(
          'd1',
          'Sign-in sheet confirms it. Correcting the record.',
          statusChangeTo: DisputeStatus.resolved,
        );

    expect(updated, isNotNull);
    expect(updated!.status, DisputeStatus.resolved);
    expect(updated.responses, hasLength(2));
    expect(updated.responses.last.statusChangeTo, DisputeStatus.resolved);
  });

  test('failures surface as error state, not throws', () async {
    final container = containerWith(_FailingDisputeRepo());
    final sub = container.listen(disputeFormControllerProvider, (_, _) {});
    final controller = container.read(disputeFormControllerProvider.notifier);

    expect(
      await controller.raise(category: DisputeCategory.other, summary: 'x'),
      isNull,
    );
    expect(sub.read().hasError, isTrue);

    expect(await controller.respond('d1', 'x'), isNull);
    expect(sub.read().hasError, isTrue);
  });
}
