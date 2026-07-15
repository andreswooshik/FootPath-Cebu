import 'package:flutter/foundation.dart';

import 'package:footpath_cebu/domain/entities/age_tier.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';
import 'package:footpath_cebu/domain/usecases/get_squad.dart';

/// Drives the Coach dashboard's Active Squad Roster.
///
/// Holds only presentation state and business logic (loading, search filter,
/// derived counts). It depends on the [GetSquad] use case (which wraps the
/// narrow SquadRepository — ISP), not a concrete Firebase/HTTP class — so it
/// can be unit-tested with a fake.
class CoachDashboardViewModel extends ChangeNotifier {
  CoachDashboardViewModel(this._getSquad);

  final GetSquad _getSquad;

  List<Player> _squad = const [];
  bool _loading = false;
  String? _error;
  String _query = '';
  AgeTier? _tierFilter;

  bool get isLoading => _loading;
  String? get error => _error;
  String get query => _query;

  /// The tier the roster is filtered to, or null for the whole squad.
  AgeTier? get tierFilter => _tierFilter;

  /// Total players registered to the squad (unfiltered) — the roster header
  /// keeps reporting the true squad size while the grid shows a subset.
  int get registeredCount => _squad.length;

  /// How many players sit in [tier], ignoring the search query. Shown on the
  /// filter chips so an empty tier is obvious before the coach taps it.
  int countFor(AgeTier tier) =>
      _squad.where((p) => p.ageTier == tier).length;

  /// The roster after applying the tier filter and the search query.
  List<Player> get players {
    var result = _squad;
    final tier = _tierFilter;
    if (tier != null) {
      result = result.where((p) => p.ageTier == tier).toList(growable: false);
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      result = result
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.position.toLowerCase().contains(q))
          .toList(growable: false);
    }
    return result;
  }

  /// Loads the squad from the repository. Safe to call again to refresh.
  Future<void> loadSquad() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _squad = await _getSquad();
    } on PlayerRepositoryException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Something went wrong loading the roster.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Updates the search query and re-filters the visible roster.
  void search(String query) {
    _query = query.trim();
    notifyListeners();
  }

  /// Filters the roster to [tier], or clears the filter when null.
  void filterByTier(AgeTier? tier) {
    _tierFilter = tier;
    notifyListeners();
  }
}
