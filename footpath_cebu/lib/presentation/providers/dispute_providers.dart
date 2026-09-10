import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/presentation/providers/mutation_controller.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/dispute.dart';

class DisputeListState {
  const DisputeListState({
    required this.items,
    required this.nextOffset,
    this.isLoadingMore = false,
    this.loadMoreError,
  });

  final List<Dispute> items;
  final int? nextOffset;
  final bool isLoadingMore;
  final Object? loadMoreError;

  bool get hasMore => nextOffset != null;

  DisputeListState copyWith({
    List<Dispute>? items,
    int? nextOffset,
    bool clearNextOffset = false,
    bool? isLoadingMore,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) => DisputeListState(
    items: items ?? this.items,
    nextOffset: clearNextOffset ? null : nextOffset ?? this.nextOffset,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    loadMoreError: clearLoadMoreError
        ? null
        : loadMoreError ?? this.loadMoreError,
  );
}

class DisputeListController extends AsyncNotifier<DisputeListState> {
  static const pageSize = 50;

  @override
  Future<DisputeListState> build() => _firstPage();

  Future<DisputeListState> _firstPage() async {
    final page = await ref
        .read(getDisputesProvider)
        .page(offset: 0, limit: pageSize);
    return DisputeListState(items: page.items, nextOffset: page.nextOffset);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(_firstPage);
    if (ref.mounted) state = result;
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) return;
    state = AsyncData(
      current.copyWith(isLoadingMore: true, clearLoadMoreError: true),
    );
    try {
      final page = await ref
          .read(getDisputesProvider)
          .page(offset: current.nextOffset!, limit: pageSize);
      if (!ref.mounted) return;
      state = AsyncData(
        DisputeListState(
          items: List.unmodifiable([...current.items, ...page.items]),
          nextOffset: page.nextOffset,
        ),
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = AsyncData(
        current.copyWith(isLoadingMore: false, loadMoreError: error),
      );
    }
  }
}

final disputesProvider =
    AsyncNotifierProvider.autoDispose<DisputeListController, DisputeListState>(
      DisputeListController.new,
    );

final disputeDetailProvider = FutureProvider.autoDispose
    .family<Dispute, String>((ref, id) => ref.watch(getDisputeProvider)(id));

/// Drives the flag-dispute form and the respond action.
///
/// Owns only the submit state ([AsyncValue] loading/error); field values live
/// in the screens — same shape as [InjuryFormController].
class DisputeFormController extends MutationController {
  /// Flags a new dispute. Returns it on success, or null on failure (with
  /// the error in [state] for the View to show).
  Future<Dispute?> raise({
    required DisputeCategory category,
    required String summary,
    String? detail,
    String? subjectPlayerId,
  }) async {
    return runMutation(
      () async {
        final dispute = await ref.read(raiseDisputeProvider)(
          category: category,
          summary: summary,
          detail: detail,
          subjectPlayerId: subjectPlayerId,
        );
        return dispute;
      },
      onSuccess: (result) {
        ref.invalidate(disputesProvider);
      },
    );
  }

  /// Appends a response (optionally moving the status). Returns the updated
  /// dispute on success, or null on failure.
  Future<Dispute?> respond(
    String disputeId,
    String body, {
    DisputeStatus? statusChangeTo,
  }) async {
    return runMutation(
      () async {
        final dispute = await ref.read(respondToDisputeProvider)(
          disputeId,
          body,
          statusChangeTo: statusChangeTo,
        );
        return dispute;
      },
      onSuccess: (result) {
        ref.invalidate(disputesProvider);
        ref.invalidate(disputeDetailProvider(disputeId));
      },
    );
  }
}

final disputeFormControllerProvider =
    AsyncNotifierProvider.autoDispose<DisputeFormController, void>(
      DisputeFormController.new,
    );
