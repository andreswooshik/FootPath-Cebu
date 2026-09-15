import 'package:flutter/foundation.dart';

/// App-wide guard for notification UI while protected player data is locked.
///
/// Each mounted privacy gate owns a token. This keeps the guard active when
/// multiple protected tabs are retained in an IndexedStack and only releases
/// it after the final gate is gone or unlocked.
class PrivacyNotificationGuard extends ChangeNotifier {
  final Set<Object> _tokens = <Object>{};

  bool get isActive => _tokens.isNotEmpty;

  void activate(Object token) {
    final wasActive = isActive;
    _tokens.add(token);
    if (!wasActive) notifyListeners();
  }

  void deactivate(Object token) {
    final wasActive = isActive;
    _tokens.remove(token);
    if (wasActive && !isActive) notifyListeners();
  }
}

final privacyNotificationGuard = PrivacyNotificationGuard();
