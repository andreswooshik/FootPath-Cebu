import 'package:flutter/foundation.dart';

import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/domain/repositories/training_repository.dart';
import 'package:footpath_cebu/domain/usecases/schedule_training_session.dart';

/// Drives the Schedule New Session form.
///
/// Owns only the submit state (saving / error); the form field values live in
/// the screen and are handed over as a draft [TrainingSession]. Depends on the
/// [ScheduleTrainingSession] use case, not a concrete repository.
class ScheduleSessionViewModel extends ChangeNotifier {
  ScheduleSessionViewModel(this._schedule);

  final ScheduleTrainingSession _schedule;

  bool _saving = false;
  String? _error;

  bool get isSaving => _saving;
  String? get error => _error;

  /// Persists [draft]. Returns true on success so the screen can pop back to
  /// the schedule and refresh it.
  Future<bool> submit(TrainingSession draft) async {
    _saving = true;
    _error = null;
    notifyListeners();
    try {
      await _schedule(draft);
      return true;
    } on TrainingRepositoryException catch (e) {
      _error = e.message;
      return false;
    } catch (_) {
      _error = 'Could not schedule the session. Please try again.';
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}
