import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:footpath_cebu/core/di/providers.dart';
import 'package:footpath_cebu/domain/entities/attendance.dart';
import 'package:footpath_cebu/domain/entities/player.dart';
import 'package:footpath_cebu/presentation/providers/player_privacy_pin_providers.dart';

/// The guardian's linked children. Refresh with
/// `ref.refresh(linkedPlayersProvider.future)`.
final linkedPlayersProvider = FutureProvider.autoDispose<List<Player>>(
  (ref) => ref.watch(getLinkedPlayersProvider)(),
);

/// Which child the guardian is looking at. Null until they pick one — the
/// derived [selectedChildProvider] falls back to the first linked child.
class SelectedChildIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String childId) {
    if (state == childId) return;

    // An unlock grant belongs to one deliberate profile-viewing action. When
    // the guardian changes players, discard every cached grant before showing
    // the new profile so selecting it again always requires a fresh PIN.
    ref.read(privacyUnlockedPlayersProvider.notifier).clear();
    state = childId;
  }
}

final selectedChildIdProvider =
    NotifierProvider.autoDispose<SelectedChildIdNotifier, String?>(
      SelectedChildIdNotifier.new,
    );

/// The child whose card and attendance are on screen, or null before the
/// children have loaded (or when the guardian has no linked players).
final selectedChildProvider = Provider.autoDispose<Player?>((ref) {
  final children = ref.watch(linkedPlayersProvider).value ?? const <Player>[];
  if (children.isEmpty) return null;
  final id = ref.watch(selectedChildIdProvider);
  if (id == null) return null;
  for (final child in children) {
    if (child.id == id) return child;
  }
  return null;
});

/// Full profile data is fetched only after the server has issued a short-lived
/// player unlock grant. The selector remains intentionally redacted.
final selectedChildDetailsProvider = FutureProvider.autoDispose
    .family<Player, String>((ref, playerId) {
      ref.watch(privacyUnlockedPlayersProvider);
      final token = ref
          .watch(playerUnlockTokenStoreProvider)
          .tokenFor(playerId);
      return ref.watch(getPlayerDetailsProvider)(playerId, unlockToken: token);
    });

/// Attendance records for one player. A family so switching children swaps to
/// (and caches) that child's records instead of clobbering shared state.
final childAttendanceProvider = FutureProvider.autoDispose
    .family<List<Attendance>, String>(
      (ref, playerId) => ref.watch(getPlayerAttendanceProvider)(playerId),
    );

/// Summary of an attendance list, for the Guardian dashboard's stat tiles.
extension AttendanceSummary on List<Attendance> {
  /// Most recent three records, for the "Recent Attendance" section.
  List<Attendance> get recent => take(3).toList();

  int get sessionCount => length;

  /// Percentage of recorded sessions the child was present for (0–100).
  int get presentPercent {
    if (isEmpty) return 0;
    final present = where((a) => a.status == AttendanceStatus.present).length;
    return ((present / length) * 100).round();
  }

  /// Consecutive most-recent sessions the player showed up for. The list is
  /// ordered newest-first, so this counts leading "present" records — the
  /// streak the dashboard celebrates ("3 sessions in a row 🔥").
  int get currentStreak {
    var streak = 0;
    for (final a in this) {
      if (a.status != AttendanceStatus.present) break;
      streak++;
    }
    return streak;
  }
}
