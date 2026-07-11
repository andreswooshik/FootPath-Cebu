import 'package:flutter/foundation.dart';

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

  bool get isLoading => _loading;
  String? get error => _error;
  String get query => _query;

  /// Total players registered to the squad (unfiltered).
  int get registeredCount => _squad.length;

  /// The roster after applying the current search query.
  List<Player> get players {
    if (_query.isEmpty) return _squad;
    final q = _query.toLowerCase();
    return _squad
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.position.toLowerCase().contains(q))
        .toList(growable: false);
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
}
