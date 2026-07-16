import 'package:flutter/foundation.dart';

import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';
import 'package:footpath_cebu/domain/usecases/save_player_assessment.dart';

/// Drives the coach's Edit Performance Data form.
///
/// Owns only the submit state (saving / error); the slider values live in the
/// screen and are handed over as a [PlayerRatings] draft. Depends on the
/// [SavePlayerAssessment] use case, not a concrete repository.
class EditPerformanceViewModel extends ChangeNotifier {
  EditPerformanceViewModel(this._save);

  final SavePlayerAssessment _save;

  bool _saving = false;
  String? _error;

  bool get isSaving => _saving;
  String? get error => _error;

  /// Persists [ratings] for [playerId]. Returns the updated player on success,
  /// or null on failure (with [error] set for the View to show).
  Future<Player?> submit(String playerId, PlayerRatings ratings) async {
    _saving = true;
    _error = null;
    notifyListeners();
    try {
      return await _save(playerId, ratings);
    } on PlayerRepositoryException catch (e) {
      _error = e.message;
      return null;
    } catch (_) {
      _error = 'Could not save the assessment. Please try again.';
      return null;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}
