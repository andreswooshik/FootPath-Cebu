import 'package:flutter/foundation.dart';

import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';
import 'package:footpath_cebu/domain/usecases/get_linked_players.dart';

/// Drives the Guardian dashboard — a read-only list of the guardian's linked
/// children. Business logic only; no Firebase/HTTP.
class GuardianDashboardViewModel extends ChangeNotifier {
  GuardianDashboardViewModel(this._getLinkedPlayers);

  final GetLinkedPlayers _getLinkedPlayers;

  List<Player> _children = const [];
  bool _loading = false;
  String? _error;

  List<Player> get children => _children;
  bool get isLoading => _loading;
  String? get error => _error;
  int get childCount => _children.length;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _children = await _getLinkedPlayers();
    } on PlayerRepositoryException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Something went wrong loading your children.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
