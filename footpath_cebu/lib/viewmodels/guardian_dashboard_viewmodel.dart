import 'package:flutter/foundation.dart';

import '../models/player.dart';
import '../repositories/player_repository.dart';

/// Drives the Guardian dashboard — a read-only list of the guardian's linked
/// children. Business logic only; no Firebase/HTTP.
class GuardianDashboardViewModel extends ChangeNotifier {
  GuardianDashboardViewModel(this._repository);

  final LinkedPlayersRepository _repository;

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
      _children = await _repository.fetchLinkedPlayers();
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
