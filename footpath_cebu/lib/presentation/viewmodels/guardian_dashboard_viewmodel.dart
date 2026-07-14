import 'package:flutter/foundation.dart';

import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/attendance_repository.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';
import 'package:footpath_cebu/domain/usecases/get_linked_players.dart';
import 'package:footpath_cebu/domain/usecases/get_player_attendance.dart';

/// Drives the Guardian dashboard — the guardian picks one of their linked
/// children and sees that child's card, eligibility, and attendance summary.
/// Read-only: business logic only, no Firebase/HTTP.
class GuardianDashboardViewModel extends ChangeNotifier {
  GuardianDashboardViewModel(this._getLinkedPlayers, this._getPlayerAttendance);

  final GetLinkedPlayers _getLinkedPlayers;
  final GetPlayerAttendance _getPlayerAttendance;

  List<Player> _children = const [];
  String? _selectedChildId;
  List<Attendance> _attendance = const [];
  bool _loadingChildren = false;
  bool _loadingAttendance = false;
  String? _error;

  List<Player> get children => _children;
  int get childCount => _children.length;
  bool get isLoading => _loadingChildren;
  bool get isLoadingAttendance => _loadingAttendance;
  String? get error => _error;

  /// The currently selected child, or null before children have loaded.
  Player? get selectedChild {
    if (_children.isEmpty) return null;
    return _children.firstWhere(
      (c) => c.id == _selectedChildId,
      orElse: () => _children.first,
    );
  }

  List<Attendance> get attendance => _attendance;

  /// Most recent three records, for the "Recent Attendance" section.
  List<Attendance> get recentAttendance => _attendance.take(3).toList();

  int get sessionCount => _attendance.length;

  /// Percentage of recorded sessions the child was present for (0–100).
  int get attendancePercent {
    if (_attendance.isEmpty) return 0;
    final present =
        _attendance.where((a) => a.status == AttendanceStatus.present).length;
    return ((present / _attendance.length) * 100).round();
  }

  /// Loads the guardian's linked children, then the attendance for the first.
  Future<void> load() async {
    _loadingChildren = true;
    _error = null;
    notifyListeners();
    try {
      _children = await _getLinkedPlayers();
      _selectedChildId ??= _children.isEmpty ? null : _children.first.id;
    } on PlayerRepositoryException catch (e) {
      _error = e.message;
      _loadingChildren = false;
      notifyListeners();
      return;
    } catch (_) {
      _error = 'Something went wrong loading your children.';
      _loadingChildren = false;
      notifyListeners();
      return;
    }
    _loadingChildren = false;
    notifyListeners();
    await _loadAttendance();
  }

  /// Switches the active child and reloads their attendance.
  Future<void> selectChild(String childId) async {
    if (childId == _selectedChildId) return;
    _selectedChildId = childId;
    notifyListeners();
    await _loadAttendance();
  }

  Future<void> _loadAttendance() async {
    final child = selectedChild;
    if (child == null) return;
    _loadingAttendance = true;
    notifyListeners();
    try {
      _attendance = await _getPlayerAttendance(child.id);
    } on AttendanceRepositoryException catch (e) {
      _error = e.message;
      _attendance = const [];
    } catch (_) {
      _error = 'Something went wrong loading attendance.';
      _attendance = const [];
    } finally {
      _loadingAttendance = false;
      notifyListeners();
    }
  }
}
