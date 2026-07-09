import 'package:flutter/foundation.dart';

import '../models/player.dart';
import '../repositories/player_repository.dart';

/// Drives the Player dashboard — the signed-in player's own profile card,
/// eligibility status, and summary. Business logic only; no Firebase/HTTP.
class PlayerDashboardViewModel extends ChangeNotifier {
  PlayerDashboardViewModel(this._repository);

  final PlayerRepository _repository;

  Player? _player;
  bool _loading = false;
  String? _error;

  Player? get player => _player;
  bool get isLoading => _loading;
  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _player = await _repository.fetchMyProfile();
    } on PlayerRepositoryException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Something went wrong loading your profile.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
