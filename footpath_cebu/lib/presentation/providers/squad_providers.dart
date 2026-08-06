import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/entities/player_position.dart';

/// The coach's full squad roster, shared by the Coach dashboard and the
/// Coach profile snapshot. autoDispose: refetched when the coach navigates
/// back in, matching the lifecycle of the ViewModels this replaces.
/// Pull-to-refresh is `ref.refresh(squadProvider.future)`.
final squadProvider = FutureProvider.autoDispose<List<Player>>(
  (ref) => ref.watch(getSquadProvider)(),
);

/// The Coach dashboard's roster filter: a search query plus an optional
/// age-tier, applied together by [filteredSquadProvider].
class RosterFilter {
  const RosterFilter({this.query = '', this.tier});

  final String query;

  /// The tier the roster is filtered to, or null for the whole squad.
  final AgeTier? tier;

  List<Player> apply(List<Player> squad) {
    var result = squad;
    final t = tier;
    if (t != null) {
      result = result.where((p) => p.ageTier == t).toList(growable: false);
    }
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      result = result
          .where(
            (p) =>
                p.name.toLowerCase().contains(q) ||
                // Match the code ("st") or the full name ("striker"); an
                // unassigned player simply never matches a position query.
                (p.position?.code.toLowerCase().contains(q) ?? false) ||
                (p.position?.label.toLowerCase().contains(q) ?? false),
          )
          .toList(growable: false);
    }
    return result;
  }
}

class RosterFilterNotifier extends Notifier<RosterFilter> {
  @override
  RosterFilter build() => const RosterFilter();

  /// Updates the search query; the filtered roster recomputes automatically.
  void search(String query) =>
      state = RosterFilter(query: query.trim(), tier: state.tier);

  /// Filters the roster to [tier], or clears the filter when null.
  void filterByTier(AgeTier? tier) =>
      state = RosterFilter(query: state.query, tier: tier);
}

final rosterFilterProvider =
    NotifierProvider.autoDispose<RosterFilterNotifier, RosterFilter>(
      RosterFilterNotifier.new,
    );

/// The roster after applying the tier filter and the search query — derived
/// state that recomputes whenever the squad, the filter, or the query change.
final filteredSquadProvider = Provider.autoDispose<AsyncValue<List<Player>>>((
  ref,
) {
  final filter = ref.watch(rosterFilterProvider);
  return ref.watch(squadProvider).whenData(filter.apply);
});
