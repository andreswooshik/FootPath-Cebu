import 'package:flutter/foundation.dart';

import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/domain/repositories/auth_repository.dart';
import 'package:footpath_cebu/domain/repositories/player_repository.dart';
import 'package:footpath_cebu/domain/usecases/get_squad.dart';
import 'package:footpath_cebu/domain/usecases/send_password_reset.dart';
import 'package:footpath_cebu/domain/usecases/sign_out.dart';

/// Drives the Coach profile screen — the signed-in coach's account actions and
/// a snapshot of their squad.
///
/// Holds presentation state and business logic only; no Firebase/HTTP. Depends
/// on the narrow [GetSquad], [SignOut] and [SendPasswordReset] use cases rather
/// than concrete repositories (Dependency Inversion), so it is unit-testable
/// with fakes and cannot reach reads it has no business touching.
class CoachProfileViewModel extends ChangeNotifier {
  CoachProfileViewModel(this._getSquad, this._signOut, this._sendPasswordReset);

  final GetSquad _getSquad;
  final SignOut _signOut;
  final SendPasswordReset _sendPasswordReset;

  List<Player> _squad = const [];
  bool _loading = false;
  bool _sendingReset = false;
  String? _error;

  bool get isLoading => _loading;
  bool get isSendingReset => _sendingReset;
  String? get error => _error;

  /// Total players on the coach's roster.
  int get registeredCount => _squad.length;

  /// Players cleared by School Staff to play.
  int get eligibleCount =>
      _squad.where((p) => p.eligibility == EligibilityStatus.eligible).length;

  /// Players on an academic warning or blocked from selection.
  int get needsAttentionCount => _squad
      .where((p) =>
          p.eligibility == EligibilityStatus.academicWarning ||
          p.eligibility == EligibilityStatus.notEligible)
      .length;

  /// Loads the squad snapshot. Safe to call again to refresh.
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _squad = await _getSquad();
    } on PlayerRepositoryException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Something went wrong loading your squad.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() => _signOut();

  /// Emails a password-reset link to the signed-in coach. Returns true on
  /// success so the View can confirm.
  Future<bool> sendPasswordReset(String email) async {
    _sendingReset = true;
    _error = null;
    notifyListeners();
    try {
      await _sendPasswordReset(email: email);
      return true;
    } on AuthException catch (e) {
      _error = e.message;
      return false;
    } catch (_) {
      _error = 'Could not send the reset email. Please try again.';
      return false;
    } finally {
      _sendingReset = false;
      notifyListeners();
    }
  }
}
