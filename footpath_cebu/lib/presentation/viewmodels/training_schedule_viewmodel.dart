import 'package:flutter/foundation.dart';

import 'package:footpath_cebu/domain/entities/training_session.dart';
import 'package:footpath_cebu/domain/repositories/training_repository.dart';
import 'package:footpath_cebu/domain/usecases/get_training_sessions.dart';

/// Drives the coach's Training Schedule list.
///
/// Holds only presentation state: loading, error, and the split of the
/// schedule into Upcoming and Past by calendar day. Depends on the
/// [GetTrainingSessions] use case, not a concrete repository — so it can be
/// unit-tested with a fake.
class TrainingScheduleViewModel extends ChangeNotifier {
  TrainingScheduleViewModel(this._getSessions);

  final GetTrainingSessions _getSessions;

  List<TrainingSession> _sessions = const [];
  bool _loading = false;
  String? _error;

  bool get isLoading => _loading;
  String? get error => _error;

  /// Sessions from today onward, soonest first.
  List<TrainingSession> get upcoming {
    final list = _sessions.where((s) => !_isPast(s.date)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return List.unmodifiable(list);
  }

  /// Sessions before today, most recent first.
  List<TrainingSession> get past {
    final list = _sessions.where((s) => _isPast(s.date)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return List.unmodifiable(list);
  }

  /// Loads the schedule from the repository. Safe to call again to refresh —
  /// call it after scheduling a new session to pick up the change.
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _sessions = await _getSessions();
    } on TrainingRepositoryException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Something went wrong loading the schedule.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  bool _isPast(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return date.isBefore(today);
  }
}
